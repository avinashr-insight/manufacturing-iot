# Fast Path and Slow Path

The dataset will be broken up into two sepearte datasets: the edge database (low latency and operational data access) and Databricks (historical data).  The schemas for the tables on the edge databases will mirror the tables on Databricks.

# Edge Database 

The edge database will have a limited number of clients and contain the minimal amount of data to keep access fast.  The 
ALT API and data purging processes should be the only clients with direct access.  For reporting, users should use the Databricks
tables with will have a near real time copy of the edge database data.

For the edge database, we have chosen Postgresql.  Features include:
1. A better query optimizer than MySQL
2. Good ANSI SQL support
3. Stored procedures (if needed)
4. Widely used and well documented
5. Mature CDC implementation

Since the critical data is all in the edge database (PLMS operational data and PLMS_\<site\> in process part processing) all the entries will be able
to keep processing regardless of Azure connectivity.  

# Databricks

The Databricks data will be synced to the edge database with close to near real time latency (5 minutes or less) to allow:
1. Operational dashboards to utilize the data without impacting the edge database
2. Future curated reporting tables to be bult on top of near real time data instead of daily snapshots 
3. Machine learning operations
4. Any operation that may need to utilize a large amount of data (planned storage will be 90-100 days) 

# Edge to Databricks Synch

(see diagram _data flow detailed.drawio)

To provide a low latency way to extract data that doesn't depend on watermark queries, the system will utilize a change data capture process.
As the edge database processes inserts, deletes, and updates the edge database will populate the transaction log. The sync process will 
utilize debezium to read the transaction log entries and translate them into JSON.  Once the data is in JSON format the events will
be sent to an Azure Event Hub topic.  Once sent, the process will move on to the next entry.  If access to Azure is interrupted, the changes
will queue up locally until it is reestablished.  Once that happens, all changes will be sent to the topic to be processed by databricks.

Each schema will have it's own CDC monitor.

Once the data is in the topic, it will be read by a Databricks process that will:
- Determine the target table and group records by the table they will be getting sent to
- Look up the schema (neeeded to convert the JSON data to a reecord to insert), primary key, and if the table is purged.  These will be set via tags and looked up by querying the informamtion_schema.table_tags table.  
- If the table is purged filter out delete entries
- Apply the table schema to the JSON data
- Insert new records/Update existing records 

# MQTT Data

MQTT events are forwarded from AIO into Azure Event Hub (in JSON format).  A Databricks job will read the events from the topic.  First, it'll extract a set of fields from the JSON (line, message type, timestamp, machine) if they exist.  Next it will append to the bronze mqtt_events.   

# One time loads

(see Historical Data Loading.drawio)

There will be several one time loads that will be needed:
1. Histrocial data (data from 0-90 days in the large on-prem database)
2. Edge database (in process parts, master data) 
3. Archived data (data in the offline archive databases) if needed

For 1: We will use Azure Data Factory to load the contents of the tables SQL Server database into parquet files in a dedicated 
storage container.  Once there, a dedicated process will ingest the parquet files and create the tables.

For 2: The edge database will need to be loaded with the data that is specific to the line.

For 3 (if needed): Depends on archive size, data will be loaded into a specific storage container.  Once in, data can be queried
inside of databricks using sql.

# Purge process

(see purge process.drawio)

To keep the data in the edge database small, there will be a purge process with two facets:
1. purge PLMS non-part data
2. PLMS part data (PLMS_\<site\> schemas)

For non-part data, each table will have a TTL defined.  When the purge process runs, the process will query databricks
for the table TTL, the column that determines the TTL, and primary key column.  The process will query the edge database
table for all the potential deletes.  For each delete canidate the process will check if the value is in Databricks.  if it 
exists, the edge database record is deleted.

For part data tables (PLMS_\<site\> schema), the process will query all items that are in complete status and are above the TTL value.
for each record, the process will verify that it exists in Databricks, then delete the local copy.

If the connection to Azure is not available, both purge processes will not run.

# Non-operational data pipeline

All machine metrics and MQTT data will be forwared to an event hub topic.  A Databricks streaming job will read the events (that will be
in JSON format) and store them in a 'raw' delta table that will store the data in the JSON format.  The JSON data can be queried via SQL directly 
or pyspark.

# Data Access

(See Data access.drawio)

## ALT API

ALT API will not have direct access to the historical data in Databricks due to it's current archiecture.  A Dashboard can be constructed to lookup part data from 0 90 days.

## storage

We will be utilizing ADLS Gen2 storage accounts to store the 'warm data' (data in Databricks).  Databricks access to storage accounts
is done via a managed identity known as a 'Access Connector for Databricks'.  Once this created, the connector is given the 'Storage Blob Data 
Contributor' role.  When granted, Databricks uses this managed identity to access the storage account.  Once done, a external location is 
established.  This is a storage account URL that is associated with the access connector managed identity.  Once established, Databricks
will access the storage URL on behalf of users, functioning as the access proxy.  Via this mechanism Databricks can enforce all data access ACLs.  

Once the external location is established (container@storage account/directory) a catalog will be created using the external location as
the default storage location.  Once created, the lower schemas are created (PLMS, PLMS_<site>), then the tables (mirroring the schema
that is in the edge tables).  This setup takes advantage of Databricks managed tables, which enables using features such as Predictive 
optimization.  All tables will be under the container@storage account/directory/<catalog>/ directory with UUID directory names.  
It's not recommended to read these directories directly, but to go through the table entities.  

## Serverless Compute

The data will be accessable via two methods: Datbricks Jobs and Databricks serverless warehouses.  Note: using serverless compute 
with private endpoints requires configuration in the Databricks account console, see 
https://learn.microsoft.com/en-us/azure/databricks/security/network/serverless-network-security/serverless-private-link

Serverless compute will spin up compute quickly as needed to handle incoming queries and will shut down after a set amount of time if
there are no requests.  External applications that need to query data will connect to connect to a Databricks endpoint using the 
appropiate drivers.  Note: serverless warehouses can take 5-10 seconds to spin up, timeouts may need to be adjusted.  Power BI will 
also be connected to show near real time dashboards.


## Archiving Data (data older than 100 days, short term)

Weekly a process will run across all the tables in the PLMS_\<site\> schemas that will take any record with an age > 100 days and put it in the coorsponding table in the PLMS_\<site\>_archive schema.  It will then delete the records from the source table.  For the PLMS schema, for each table with historical information it will copy the records to the corresponding table in the PLMS_ARCHIVE schema 

## Long Term Archive Plan ( data older than 100 days, long term)

Once data is older than 100 days, it will be moved to a cold tier and stored in JSON format.  

Recommendations: 
1. Once data is bundled into the final JSON format, have a table that contains paths references with a minimal number of columns to make
   searching simpler without incurring unnecessary warm up costs.
2. Run the process in Databricks environment to utilize parallel compute.  

## Loading Historical Databricks Data

An storage container will be created with a directories 
organized by schema and table.  Using the current ADF installation, data can be read and saved in parquet format in the container in the 
appropiate directory.  An external location will be configured in the Databricks workspace to allow Databricks jobs to  access to the directory.  
Once the data is written, a Databricks job will create the desintation table based on the parquet data (which will match the columns/types of 
the soruce table exactly).

## Seeding the Edge Databases

Each edge database will need to be seeded with:
1. A copy of all the tables in the PLMS Database (with some historical data)
2. Any tables from the PLMS_\<site\> schema that store the part related data for the line.

## Updating Control Data on the Edge Database

The K3s cluster will not have access to original SQL Server database, updates to configuration will be done via the ALT API instance running in the k3s cluster.  All updates will flow to Databricks via the CDC procss.

## Loading Archived Data

Depending on the data size, a solution such as Azure Data Box may be used.  Once in the storage account the data can be loaded into it's own
catalog to allow the new archive process to be developed.

# Databricks Jobs

Each line will have two streaming jobs associated with it:  One to read MQTT data and one to read the CDC messages from the edge database. 
The jobs that read CDC information will have the following paramters:
1. Lines to monitor  
2. Hours of operation for each line
3. Target catalog

Based on the line names to monitor, the job will deduce the topic names to monitor.  Each CDC message will have the source table and schema.

Each MQTT job will have the following parameters:
1. Lines to monitor
2. Hours of operation for each line
4. Target Catalog
5. Target schema (defaults to mqtt_data)

Based on the line names the job will deduce the topic names to monitor and the target table name for the MQTT data.

Due to a maximum number of concurrent jobs (1000) and other resoruce limits in Databricks, each CDC and MQTT streaming job will read more than
one line's data at once.  All streaming jobs will use job compute to keep costs lower, each job cluster will have a defined minimum (1) and max nubmer of workers to read the assigned topics.  Each line will have it's own Azure Event Hub topics for edge database replication and MQTT messages to provide 
isoliation by line.  

The streaming jobs will be designed to have operating hours defined for lines that don't operate 24/7.

A controller job will run on an interval schedule to shut down idle jobs that are monitoring lines that are outside of operating hours. 

# Topics

Each line will have two dedicated Azure Event Hub topics: one for MQTT and one for edge database replication.  

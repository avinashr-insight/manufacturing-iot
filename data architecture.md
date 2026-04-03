#Edge Database

The edge database will have a limited number of clients and contain the minimal amount of data to keep access fast.  The 
ALT API and data purging processes should be the only clients with direct access.  For reporting, users should use the Databricks
tables with will have a near real time copy of the edge database data.

The data will be replicated to Databricks via a change data capture process.  As changes are made to the database tables (insert, update, delete), the
transaction log files will be read by the change data capture process, translated to JSON, and pushed to an event hub queue (one
per monitored database).  This will allow the system to self heal when the connectivity to Azure is interrupted.  Once 
connectivity has been restored, the CDC process will pick up at the last transaction log entry and start sending data again.  Since
the critical data is all in the edge database (PLMS operational data and PLMS_<site> part processing) all the entries will be able
to keep processing regardless of Azure connectivity.  

For the edge database, we have chosen Postgresql.  Features include:
1. A better query optimizer than MySQL
2. Good ANSI SQL support
3. Stored procedures (if needed)
4. Widely used and well documented
5. Mature CDC implementation

# Purge process

To keep the data in the edge database small, there will be a purge process with two facets:
1. purge PLMS non part data
2. PLMS part data (PLMS_<site> schemas)



#Databricks 


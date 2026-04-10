Included are base deployment specs for the ALT Core API, ALT UI and flux applications.
ALT Core API is a .net application

Currently ALT_Core_API is using appsettings.json to store environment variables and keys. Recommend moving to feeding environment variables from devOps and key vault. 
Managing appsettings.json will get unwieldy as the number of deployments go up for each line and security is comprimised with storing keys in plain text and in the repo.
Flux and ALT_UI are angluar apps with environment variables stored in ClientApp/environments/environment.ts files. Recommend moving to feeding these from devOps depending on deployment location.


The script folder contains a command for creating a new mqtt broker listener. [AIOT Broker Listener](https://learn.microsoft.com/en-us/azure/iot-operations/manage-mqtt-broker/howto-configure-brokerlistener?tabs=portal%2Ctest)
An external mqtt broker listener needs to be created to accept external listeners/publishers. There is currently no authentication or TLS enabled, recommend enabling authentication and TLS.
# Configuraton script for Windows

## What does it do
Inputs: 
Assumes existence of environment variables
--customer_id $OBSERVE_CUSTOMER_ID 
--ingest_token $OBSERVE_DATASTREAM_TOKEN 

- Creates a config_files directory in home of logged in user

- Downloads configuration files from this git repository

- Installs osquery, fluentbit and telegraf

- Subsitutes values for data center, hostname, customer id, data ingest token and observe endpoint in configuration files

- Copies files to respective agent locations, renames existing files with suffix OLD

- Outputs status of services


## Steps to configure

1. Login to machine via ssh

1. Script flags
    * --customer_id = your observe customer id - REQUIRED
    * --ingest_token = your data stream ingest token from ui - REQUIRED
    * --observe_host_name = host endpoint used in config files - OPTIONAL - defaults to collect.observeinc.com
    * --config_files_clean = TRUE/FALSE whether to delete directory created for downloading config files - OPTIONAL - defaults to FALSE
    * --ec2metadata = TRUE/FALSE whether to add ec2 filter section to td-agent-bit.conf file - OPTIONAL - defaults to FALSE
        ```
        [FILTER]
            Name aws
            Match *
            imds_version v1
            az true
            ec2_instance_id true
            ec2_instance_type true
            account_id true
            hostname true
            vpc_id true
        ```
    * --datacenter = value to use for datacenter in td-agent-bit.conf and telegraf.conf files - OPTIONAL - defaults to AWS
    * --appgroup = value to use for appgroup record in td-agent-bit.conf file  - OPTIONAL - defaults to null




1. Run following script
```
Invoke-WebRequest -UseBasicParsing "https://drive.google.com/uc?export=download&id=1zofQY3Ddbk8EP5iBQtoB2-b0h2W6oc1d" -outfile .\observe-agents.zip; Expand-Archive .\observe-agents.zip -DestinationPath .\observe-agents -Force | .\observe-agents\windows-host-configuration-scripts-yasar-windows-host-config-scripts\agents.ps1 -ingest_token <<ingest_token>> -customer_id <<customer_id>> -observe_host_name <<observe_host_name>>
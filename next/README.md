# B2B Deleted Organizations Resource Cleanup Script - Documentation

This document provides detailed instructions on setting up and executing the database cleanup script. The script is designed to handle shared and identity databases in H2, MSSQL, or MySQL. It supports configurations for multiple databases as arrays, allowing flexible setups such as clustering.


## Prerequisites

1. **Supported Database Types**:
   - H2
   - MSSQL
   - MySQL

2. **Required Tools**:
   - Bash shell
   - Database drivers or relevant libraries to connect to database

---

## Script Configuration

### Configuration Variables

The script allows for specifying shared and identity databases through separate arrays, with support for multiple instances. Below is the configuration format:

### Configuration Section
```bash
# Supported DB types: h2, mssql, mysql
SHARED_DB_TYPE="mysql"     # can be h2, mssql, or mysql
IDENTITY_DB_TYPE="mysql"   # can be h2, mssql, or mysql

# Shared database configurations
<Refer below sections on how to fill this information based on the DB type>

# Identity database configurations
<Refer below sections on how to fill this information based on the DB type>

# General settings
BATCH_SIZE=10
BATCH_WAIT_TIME=100 # in milliseconds
EXPORT_FILE="/path/to/exported_data.csv" # (**MANDATORY) This will be used to save the information of organizations that is going to clean in each batch.
H2_JAR_PATH="/path/to/h2-2.2.220.jar" # This is only needed if the the database type is H2.
```

### Explanation of Variables

- **SHARED_DB_TYPE/IDENTITY_DB_TYPE**: Define the database type (`h2`, `mssql`, `mysql`).
- **SHARED_DB_* / IDENTITY_DB_***: Define respective hosts, ports, database names, users, passwords, and log directories as arrays. Each index corresponds to one database instance.
- **BATCH_SIZE**: Number of organizations processed in each batch.
- **BATCH_WAIT_TIME**: Wait time between batch executions (in milliseconds).
- **EXPORT_FILE**: File path to save exported organization data.
- **H2_JAR_PATH**: Path to the H2 database JAR file *(only needed for H2)*.

---

## Setting Up the Script

### Step 1: DB Configs

#### MySQL
---

1. First you need to install mysql cli
- **Linux:**
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install mysql-client -y
```
- **Mac:**
```bash
brew install mysql
brew services start mysql
```

2. Then update the DB configs in the `cleanup.sh` as follows,

- **Single Instance:**
    ```bash
    # Shared database configurations
    SHARED_DB_HOSTS=("127.0.0.1")
    SHARED_DB_PORTS=("3306")
    SHARED_DB_NAMES=("wso2shared_db")
    SHARED_DB_USERS=("root")
    SHARED_DB_PASSWORDS=("yourpassword")
    SHARED_DB_LOG_DIRS=("path/to/log")

    # Identity database configurations
    IDENTITY_DB_HOSTS=("127.0.0.1")
    IDENTITY_DB_PORTS=("3307")
    IDENTITY_DB_NAMES=("wso2identity_db")
    IDENTITY_DB_USERS=("root")
    IDENTITY_DB_PASSWORDS=("yourpassword")
    IDENTITY_DB_LOG_DIRS=("path/to/log")
    ```
- **Multiple Instances:** (Refer this if you have setup the database according to [Separate Databases for Clustering](https://is.docs.wso2.com/en/latest/deploy/set-up-separate-databases-for-clustering/))
    ```bash
    SHARED_DB_HOSTS=("127.0.0.1" "127.0.0.1")
    SHARED_DB_PORTS=("3306" "3306")
    SHARED_DB_NAMES=("wso2shared_db_1" "wso2shared_db_2")
    SHARED_DB_USERS=("root" "root")
    SHARED_DB_PASSWORDS=("yourpassword1" "yourpassword2")
    SHARED_DB_LOG_DIRS=("/var/log/shared1" "/var/log/shared2") # If there are 2 DBs, then 2 paths are needed for logging

    IDENTITY_DB_HOSTS=("127.0.0.1" "127.0.0.1")
    IDENTITY_DB_PORTS=("3306" "3306")
    IDENTITY_DB_NAMES=("wso2identity_db_1" "wso2identity_db_2")
    IDENTITY_DB_USERS=("root" "root")
    IDENTITY_DB_PASSWORDS=("yourpassword" "yourpassword")
    IDENTITY_DB_LOG_DIRS=("path/to/log_1" "path/to/log_2")
    ```

#### MSSQL
---

1. First you need to install `sqlcmd`
2. Then update the DB configs in the `cleanup.sh` as follows,

- **Single Instance:**
    ```bash
    # Shared database configurations
    SHARED_DB_HOSTS=("127.0.0.1")
    SHARED_DB_PORTS=("1433")
    SHARED_DB_NAMES=("wso2shared_db")
    SHARED_DB_USERS=("SA")
    SHARED_DB_PASSWORDS=("yourpassword")
    SHARED_DB_LOG_DIRS=("path/to/log")

    # Identity database configurations
    IDENTITY_DB_HOSTS=("127.0.0.1")
    IDENTITY_DB_PORTS=("1433")
    IDENTITY_DB_NAMES=("wso2identity_db")
    IDENTITY_DB_USERS=("SA")
    IDENTITY_DB_PASSWORDS=("yourpassword")
    IDENTITY_DB_LOG_DIRS=("path/to/log")
    ```
- **Multiple Instances:** (Refer this if you have setup the database according to [Seperate Databases for Clustering](https://is.docs.wso2.com/en/latest/deploy/set-up-separate-databases-for-clustering/))
    ```bash
    SHARED_DB_HOSTS=("127.0.0.1" "127.0.0.1")
    SHARED_DB_PORTS=("1433" "1433")
    SHARED_DB_NAMES=("wso2shared_db_1" "wso2shared_db_2")
    SHARED_DB_USERS=("SA" "SA")
    SHARED_DB_PASSWORDS=("yourpassword1" "yourpassword2")
    SHARED_DB_LOG_DIRS=("/var/log/shared1" "/var/log/shared2") # If there are 2 DBs, then 2 paths are needed for logging

    IDENTITY_DB_HOSTS=("127.0.0.1" "127.0.0.1")
    IDENTITY_DB_PORTS=("1433" "1433")
    IDENTITY_DB_NAMES=("wso2identity_db_1" "wso2identity_db_2")
    IDENTITY_DB_USERS=("SA" "SA")
    IDENTITY_DB_PASSWORDS=("yourpassword" "yourpassword")
    IDENTITY_DB_LOG_DIRS=("path/to/log_1" "path/to/log_2")
    ```

#### H2
---

1. Modify the `SHARED_DB_TYPE` and `IDENTITY_DB_TYPE` variables to match your database type.
2. Populate the respective arrays (`SHARED_DB_*` and `IDENTITY_DB_*`) with database details. For example:
   - **Single Instance:**
     ```bash
     SHARED_DB_URLS=("jdbc:h2:....")
     SHARED_DB_USERS=("username")
     SHARED_DB_PASSWORDS=("password")
     SHARED_DB_LOG_DIRS=("/var/log/shared")

     IDENTITY_DB_URLS=("jdbc:h2:...")
     IDENTITY_DB_USERS=("username")
     IDENTITY_DB_PASSWORDS=("password")
     IDENTITY_DB_LOG_DIRS=("/var/log/identity")
     ```
   - **Multiple Instances:** (Refer this if you have setup the database according to [Seperate Databases for Clustering](https://is.docs.wso2.com/en/latest/deploy/set-up-separate-databases-for-clustering/))
     ```bash
     SHARED_DB_URLS=("jdbc:h2:...." "jdbc:h2:...") ## Make sure that the first DB has the UM_TENANT table
     SHARED_DB_USERS=("user1" "user2")
     SHARED_DB_PASSWORDS=("password1" "password2")
     SHARED_DB_LOG_DIRS=("/var/log/shared1" "/var/log/shared2") # If there are 2 DBs, then 2 paths are needed for logging

     IDENTITY_DB_HOSTS=("jdbc:h2:...." "jdbc:h2:...")
     IDENTITY_DB_USERS=("user1" "user2")
     IDENTITY_DB_PASSWORDS=("password1" "password2")
     IDENTITY_DB_LOG_DIRS=("/var/log/identity1" "/var/log/identity2")
     ```

3. Update `H2_JAR_PATH` (only for h2) with the correct file paths.

---

### Step 2: Script Execution

Run the script with the following command:
```bash
./cleanup.sh
```

The script follows these steps:

1. **Fetch Deleted Organization Data**:
   - Uses `org_data_fetch.sh` to extract deleted organization data to process.
2. **Clean Shared Database Resources**:
   - Uses `shared_db_cleanup.sh` to clean up shared database entries.
3. **Clean Identity Database Resources**:
   - Uses `identity_db_cleanup.sh` to clean up identity database entries.
4. **Tenant Cleanup**:
   - Uses `delete_um_tenant.sh` to clean tenant information.

**The script will identify which sub bash scripts that should run according to the configurations you have define.**

### Logs and Outputs
- Logs are saved in the directories specified in the respective `*_LOG_DIRS` arrays.
- Exported data is saved to the file specified in `EXPORT_FILE`.

---

## Error Handling

- **Script Not Found**:
  Ensure all required scripts are in the correct directories.
- **Database Connection Issues**:
  Verify the database host, port, and credentials in the configuration.
- **Missing JAR File** (for H2):
  Ensure the correct path to the H2 JAR file is specified.

---

## Troubleshooting

1. **No Data to Process**:
   - Check if the database contains records to process.
   - Verify the database queries in the `org_data_fetch.sh` script.

2. **Script Errors**:
   - Ensure the script has execute permissions: `chmod +x <script_name>.sh`.

---

### Sample Configuration with MySQL
```bash
SHARED_DB_TYPE="mysql"
IDENTITY_DB_TYPE="mysql"

SHARED_DB_HOSTS=("localhost")
SHARED_DB_PORTS=("3306")
SHARED_DB_NAMES=("WSO2_SHARED_DB")
SHARED_DB_USERS=("root")
SHARED_DB_PASSWORDS=("Root1234@")
SHARED_DB_LOG_DIRS=("/var/log/shared")

IDENTITY_DB_HOSTS=("localhost")
IDENTITY_DB_PORTS=("3306")
IDENTITY_DB_NAMES=("WSO2_IDENTITY_DB")
IDENTITY_DB_USERS=("root")
IDENTITY_DB_PASSWORDS=("Root1234@")
IDENTITY_DB_LOG_DIRS=("/var/log/identity")

BATCH_SIZE=20
BATCH_WAIT_TIME=200
EXPORT_FILE="/tmp/exported_data.csv"
```

Execute the script:
```bash
bash cleanup_script.sh
```

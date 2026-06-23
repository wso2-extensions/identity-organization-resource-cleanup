#!/bin/bash

# Arguments: DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD EXPORT_FILE LOG_DIR
DB_HOST="$1"
DB_PORT="$2"
DB_NAME="$3"
DB_USER="$4"
DB_PASSWORD="$5"
EXPORT_FILE="$6"
LOG_DIR="$7"

SUMMARY_FILE="$LOG_DIR/summary.log"
SUCCESSFUL_DELETIONS_FILE="$LOG_DIR/successful_deletions.csv"

# Construct the server connection string
DB_SERVER="${DB_HOST},${DB_PORT}"

# Create a directory for query logs
mkdir -p "$LOG_DIR"

# Initialize summary log and successful deletions file
echo "Summary of Deletions:" > "$SUMMARY_FILE"
echo "TENANT_ID" > "$SUCCESSFUL_DELETIONS_FILE"

# Predefined table deletion order
TABLE_LIST=(
  "REG_RESOURCE_COMMENT"
  "REG_RESOURCE_RATING"
  "REG_RESOURCE_TAG"
  "REG_RESOURCE_PROPERTY"
  "REG_RESOURCE_HISTORY"
  "REG_SNAPSHOT"
  "REG_RESOURCE"
  "REG_COMMENT"
  "REG_RATING"
  "REG_TAG"
  "REG_PROPERTY"
  "REG_ASSOCIATION"
  "REG_PATH"
  "REG_CONTENT_HISTORY"
  "REG_CONTENT"
  "REG_LOG"
  "UM_USER_ATTRIBUTE"
  "UM_USER"
  "UM_ROLE"
  "UM_HYBRID_ROLE"
  "UM_SYSTEM_USER"
  "UM_SYSTEM_ROLE"
  "UM_PERMISSION"
  "UM_DIALECT"
  "UM_PROFILE_CONFIG"
  "UM_CLAIM"
  "UM_CLAIM_BEHAVIOR"
  "UM_DOMAIN"
  "UM_ORG_USER_ASSOCIATION"
  "UM_HYBRID_REMEMBER_ME"
  "UM_UUID_DOMAIN_MAPPER"
  "UM_GROUP_UUID_DOMAIN_MAPPER"
  "UM_ACCOUNT_MAPPING"
)

# Step 1: Validate export file
if [[ ! -f "$EXPORT_FILE" ]]; then
  echo "Export file not found: $EXPORT_FILE"
  exit 1
fi

# Step 2: Get available tables from MSSQL database
echo "Fetching available tables from MSSQL database..."
AVAILABLE_TABLES=$(sqlcmd -S "$DB_SERVER" -d "$DB_NAME" -U "$DB_USER" -P "$DB_PASSWORD" -h -1 -W -Q "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE';")

if [[ $? -ne 0 ]]; then
  echo "Failed to fetch available tables. Please check database connection and credentials."
  exit 1
fi

# Step 3: Filter TABLE_LIST to include only existing tables
DELETE_ORDER=()
for table in "${TABLE_LIST[@]}"; do
  if echo "$AVAILABLE_TABLES" | grep -qw "$table"; then
    DELETE_ORDER+=("$table")
  fi
done

echo "Starting data deletion process..."

# Step 4: Iterate through each tenant and execute delete queries
while IFS=',' read -r TENANT_ID ORG_UUID; do
  # Trim spaces
  TENANT_ID=$(echo "$TENANT_ID" | xargs)
  ORG_UUID=$(echo "$ORG_UUID" | xargs)

  if [[ -n "$TENANT_ID" && -n "$ORG_UUID" ]]; then
    echo "Processing TENANT_ID=$TENANT_ID, ORG_UUID=$ORG_UUID"

    # Construct the deletion procedure
    DELETE_PROCEDURE="BEGIN TRANSACTION;"
    for table in "${DELETE_ORDER[@]}"; do
      if [[ "$table" == "UM_ORG_USER_ASSOCIATION" ]]; then
        DELETE_PROCEDURE+="DELETE FROM $table WHERE UM_ORG_ID = '$ORG_UUID';"
      elif [[ "$table" == UM_* ]]; then
        DELETE_PROCEDURE+="DELETE FROM $table WHERE UM_TENANT_ID = $TENANT_ID;"
      elif [[ "$table" == REG_* ]]; then
        DELETE_PROCEDURE+="DELETE FROM $table WHERE REG_TENANT_ID = $TENANT_ID;"
      fi
    done
    DELETE_PROCEDURE+="COMMIT;"

    # Execute the delete procedure
    echo "Executing deletion procedure on shared database for TENANT_ID=$TENANT_ID..."
    SQL_FILE="/tmp/delete_procedure_${TENANT_ID}.sql"
    echo "$DELETE_PROCEDURE" > "$SQL_FILE"
    sqlcmd -S "$DB_SERVER" -d "$DB_NAME" -U "$DB_USER" -P "$DB_PASSWORD" -b -m 1 -i "$SQL_FILE" -o "/tmp/sql_output.log"

    # Check if the execution was successful
    if [[ $? -eq 0 ]]; then
      echo "Resources deleted for tenant ID $TENANT_ID with org ID $ORG_UUID." | tee -a "$SUMMARY_FILE"
      echo "$TENANT_ID" >> "$SUCCESSFUL_DELETIONS_FILE"
    else
      FAILED_LOG="$LOG_DIR/failed_tenant_${TENANT_ID}.log"
      mv /tmp/sql_output.log "$FAILED_LOG"
      echo "Failed to process tenant ID $TENANT_ID with org ID $ORG_UUID. Check log: $FAILED_LOG" | tee -a "$SUMMARY_FILE"
    fi

    # Clean up temporary file if it still exists
    rm -f /tmp/sql_output.log

    echo "Completed deletion for TENANT_ID=$TENANT_ID."
  else
    echo "Skipping invalid or empty line: TENANT_ID=$TENANT_ID, ORG_UUID=$ORG_UUID"
  fi
done < "$EXPORT_FILE"

echo "Data deletion process completed. Summary available at $SUMMARY_FILE."

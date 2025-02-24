#!/bin/bash

# Define database credentials
DB_URL="$1"
DB_USER="$2"
DB_PASSWORD="$3"
H2_JAR_PATH="$4"
EXPORT_FILE="$5"
LOG_DIR="$6"
SUMMARY_FILE="$LOG_DIR/summary.log"
SUCCESSFUL_DELETIONS_FILE="$LOG_DIR/successful_deletions.csv"

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

# Function to retrieve available tables from the database
get_available_tables() {
  java -cp "$H2_JAR_PATH" org.h2.tools.Shell -url "$DB_URL" -user "$DB_USER" -password "$DB_PASSWORD" \
  -sql "SHOW TABLES;" | grep -E '^[A-Z]' | awk '{print $1}'
}

# Step 1: Get available tables from the database
echo "Fetching available tables from the database..."
AVAILABLE_TABLES=$(get_available_tables)

# Step 2: Filter tables that exist in both TABLE_LIST and AVAILABLE_TABLES
DELETE_ORDER=()
for table in "${TABLE_LIST[@]}"; do
  if echo "$AVAILABLE_TABLES" | grep -qw "$table"; then
    DELETE_ORDER+=("$table")
  fi
done

# Check if the export file exists
if [[ ! -f "$EXPORT_FILE" ]]; then
  echo "Export file not found: $EXPORT_FILE"
  exit 1
fi

# Step 3: Iterate through each tenant and execute delete queries
echo "Starting data deletion process..."
while IFS=',' read -r TENANT_ID ORG_UUID; do
  # Trim leading and trailing spaces
  TENANT_ID=$(echo "$TENANT_ID" | xargs)
  ORG_UUID=$(echo "$ORG_UUID" | xargs)

  if [[ -n "$TENANT_ID" && -n "$ORG_UUID" ]]; then
    echo "Processing TENANT_ID=$TENANT_ID, ORG_UUID=$ORG_UUID"

    # Generate the delete procedure dynamically
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
    echo "Executing deletion procedure for TENANT_ID=$TENANT_ID..."
    echo "$DELETE_PROCEDURE" | java -cp "$H2_JAR_PATH" org.h2.tools.Shell -url "$DB_URL" -user "$DB_USER" -password "$DB_PASSWORD" 2>&1 > /tmp/sql_output.log

    # Check if the execution was successful
    if [[ $? -eq 0 ]]; then
        echo "Resources deleted for tenant ID $TENANT_ID with org ID $ORG_UUID." | tee -a "$SUMMARY_FILE"
        echo "$TENANT_ID" >> "$SUCCESSFUL_DELETIONS_FILE"
    else
        FAILED_LOG="$LOG_DIR/failed_tenant_${TENANT_ID}.log"
        mv /tmp/sql_output.log "$FAILED_LOG"
        echo "Failed to process tenant ID $TENANT_ID with org ID $ORG_UUID. Check log: $FAILED_LOG" | tee -a "$SUMMARY_FILE"
    fi

    # Clean up temporary files
    rm -f /tmp/sql_output.log

    echo "Completed deletion for TENANT_ID=$TENANT_ID."
  else
    echo "Skipping invalid or empty line: TENANT_ID=$TENANT_ID, ORG_UUID=$ORG_UUID"
  fi
done < "$EXPORT_FILE"

echo "Data deletion process completed. Summary available at $SUMMARY_FILE."

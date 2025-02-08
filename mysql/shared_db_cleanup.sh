#!/bin/bash

# Arguments: DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD EXPORT_FILE LOG_DIR
DB_HOST="$1"
DB_PORT="$2"
DB_NAME="$3"
DB_USER="$4"
DB_PASSWORD="$5"
EXPORT_FILE="$6"
LOG_DIR="$7"

# Export MySQL password to suppress password warnings
export MYSQL_PWD="$DB_PASSWORD"

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

# Step 1: Validate export file
if [[ ! -f "$EXPORT_FILE" ]]; then
  echo "Export file not found: $EXPORT_FILE"
  exit 1
fi

# Step 2: Get available tables from MySQL database
echo "Fetching available tables from MySQL database..."
AVAILABLE_TABLES=$(mysql -h "$DB_HOST" -P "$DB_PORT" -D "$DB_NAME" -u "$DB_USER" -Bse "SHOW TABLES;")

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
    DELETE_PROCEDURE=""
    for table in "${DELETE_ORDER[@]}"; do
      if [[ "$table" == "UM_ORG_USER_ASSOCIATION" ]]; then
        DELETE_PROCEDURE+="DELETE FROM $table WHERE UM_ORG_ID = '$ORG_UUID';"
      elif [[ "$table" == UM_* ]]; then
        DELETE_PROCEDURE+="DELETE FROM $table WHERE UM_TENANT_ID = $TENANT_ID;"
      elif [[ "$table" == REG_* ]]; then
        DELETE_PROCEDURE+="DELETE FROM $table WHERE REG_TENANT_ID = $TENANT_ID;"
      fi
    done

    # Execute the delete procedure
    echo "Executing deletion procedure on shared database for TENANT_ID=$TENANT_ID..."
    mysql -h "$DB_HOST" -P "$DB_PORT" -D "$DB_NAME" -u "$DB_USER" -e "$DELETE_PROCEDURE" --silent > /dev/null 2>&1

    # Check if the execution was successful
    if [[ $? -eq 0 ]]; then
      echo "Resources deleted for tenant ID $TENANT_ID with org ID $ORG_UUID." | tee -a "$SUMMARY_FILE"
      echo "$TENANT_ID" >> "$SUCCESSFUL_DELETIONS_FILE"
    else
      FAILED_LOG="$LOG_DIR/failed_tenant_${TENANT_ID}.log"
      echo "$DELETE_PROCEDURE" > "$FAILED_LOG"
      echo "Failed to process tenant ID $TENANT_ID with org ID $ORG_UUID. Check log: $FAILED_LOG" | tee -a "$SUMMARY_FILE"
    fi

    echo "Completed deletion for TENANT_ID=$TENANT_ID."
  else
    echo "Skipping invalid or empty line: TENANT_ID=$TENANT_ID, ORG_UUID=$ORG_UUID"
  fi
done < "$EXPORT_FILE"

echo "Data deletion process completed. Summary available at $SUMMARY_FILE."

# Unset MYSQL_PWD to avoid leaving it in the environment
unset MYSQL_PWD

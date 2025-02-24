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

# Create necessary directories
mkdir -p "$LOG_DIR"

# Initialize summary log and successful deletions file
echo "Summary of Deletions:" > "$SUMMARY_FILE"
echo "TENANT_ID" > "$SUCCESSFUL_DELETIONS_FILE"

# Predefined table deletion order
TABLE_LIST=(
  "IDN_OAUTH_CONSUMER_APPS"
  "IDN_OAUTH2_SCOPE"
  "SP_APP"
  "IDP"
  "IDN_CLAIM_DIALECT"
  "IDN_CONFIG_RESOURCE"
  "IDN_REMOTE_FETCH_CONFIG"
  "IDN_CORS_ORIGIN"
  "IDN_SECRET"
  "API_RESOURCE"
  "IDN_AUTH_USER"
  "IDN_AUTH_SESSION_STORE"
  "IDN_AUTH_TEMP_SESSION_STORE"
  "IDN_AUTH_WAIT_STATUS"
  "IDN_SCIM_GROUP"
  "IDN_OPENID_REMEMBER_ME"
  "IDN_OPENID_USER_RPS"
  "IDN_OPENID_ASSOCIATIONS"
  "IDN_IDENTITY_USER_DATA"
  "IDN_IDENTITY_META_DATA"
  "IDN_THRIFT_SESSION"
  "FIDO_DEVICE_STORE"
  "FIDO2_DEVICE_STORE"
  "IDN_USER_ACCOUNT_ASSOCIATION"
  "IDN_RECOVERY_DATA"
  "IDN_PASSWORD_HISTORY_DATA"
  "IDN_OIDC_JTI"
  "IDN_OAUTH2_USER_CONSENT"
  "IDN_USER_FUNCTIONALITY_MAPPING"
  "IDN_USER_FUNCTIONALITY_PROPERTY"
  "IDN_FUNCTION_LIBRARY"
  "IDVP"
  "IDN_ORG_USER_INVITATION"
  "IDN_OAUTH2_ACCESS_TOKEN_AUDIT"
  "SP_TEMPLATE"
  "IDN_CERTIFICATE"
  "IDN_ACTION_PROPERTIES"
  "IDN_ACTION"
)

# Validate export file
if [[ ! -f "$EXPORT_FILE" || ! -s "$EXPORT_FILE" ]]; then
  echo "Export file is missing or empty. Exiting."
  exit 1
fi

echo "Fetching available tables from MySQL database..."
# Fetch available tables from MySQL
AVAILABLE_TABLES=$(mysql -h "$DB_HOST" -P "$DB_PORT" -D "$DB_NAME" -u "$DB_USER" -Bse "SHOW TABLES;")

if [[ $? -ne 0 ]]; then
  echo "Failed to fetch available tables. Please check database connection and credentials."
  exit 1
fi

# Filter TABLE_LIST to include only tables that exist in AVAILABLE_TABLES
DELETE_ORDER=()
for table in "${TABLE_LIST[@]}"; do
  if echo "$AVAILABLE_TABLES" | grep -qw "$table"; then
    DELETE_ORDER+=("$table")
  fi
done

echo "Tables to delete in order: ${DELETE_ORDER[*]}"

echo "Starting data deletion process..."
while IFS=',' read -r TENANT_ID ORG_UUID; do
  # Trim and sanitize TENANT_ID, ORG_UUID
  TENANT_ID=$(echo "$TENANT_ID" | xargs | sed 's/[^a-zA-Z0-9-]//g')
  ORG_UUID=$(echo "$ORG_UUID" | xargs | sed 's/[^a-zA-Z0-9-]//g')

  if [[ -n "$TENANT_ID" && -n "$ORG_UUID" ]]; then
    echo "Processing TENANT_ID=$TENANT_ID, ORG_UUID=$ORG_UUID"

    # Generate the delete procedure dynamically
    DELETE_PROCEDURE=""
    for table in "${DELETE_ORDER[@]}"; do
      if [[ "$table" == "IDN_ORG_USER_INVITATION" ]]; then
        DELETE_PROCEDURE+="DELETE FROM $table WHERE INVITED_ORG_ID = '$ORG_UUID';"
      else
        DELETE_PROCEDURE+="DELETE FROM $table WHERE TENANT_ID = $TENANT_ID;"
      fi
    done

    # Execute the delete procedure
    echo "Executing deletion procedure on identity database for TENANT_ID=$TENANT_ID..."
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
  else
    echo "Skipping invalid or empty line: TENANT_ID=$TENANT_ID, ORG_UUID=$ORG_UUID"
  fi
done < "$EXPORT_FILE"

echo "Data deletion process completed. Summary available at $SUMMARY_FILE."

# Unset MYSQL_PWD to avoid leaving it in the environment
unset MYSQL_PWD

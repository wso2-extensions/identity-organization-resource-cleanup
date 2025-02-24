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
)

# Retrieve available tables
echo "Fetching available tables from the database..."
AVAILABLE_TABLES=$(java -cp "$H2_JAR_PATH" org.h2.tools.Shell -url "$DB_URL" -user "$DB_USER" -password "$DB_PASSWORD" -sql "SHOW TABLES;" | grep -E '^[A-Z]' | awk '{print $1}')

# Filter tables
DELETE_ORDER=()
for table in "${TABLE_LIST[@]}"; do
  if echo "$AVAILABLE_TABLES" | grep -qw "$table"; then
    DELETE_ORDER+=("$table")
  fi
done
echo "Tables to delete in order: ${DELETE_ORDER[*]}" >> "$SUMMARY_FILE"

# Validate export file
if [[ ! -f "$EXPORT_FILE" || ! -s "$EXPORT_FILE" ]]; then
  echo "Export file is missing or empty. Exiting."
  exit 1
fi

# Process tenants
echo "Starting data deletion process..."
while IFS=',' read -r TENANT_ID ORG_UUID; do
  TENANT_ID=$(echo "$TENANT_ID" | xargs | sed 's/[^a-zA-Z0-9-]//g')
  ORG_UUID=$(echo "$ORG_UUID" | xargs | sed 's/[^a-zA-Z0-9-]//g')

  if [[ -n "$TENANT_ID" && -n "$ORG_UUID" ]]; then
    echo "Processing TENANT_ID=$TENANT_ID, ORG_UUID=$ORG_UUID"

    DELETE_PROCEDURE="SET REFERENTIAL_INTEGRITY FALSE; BEGIN TRANSACTION;"
    for table in "${DELETE_ORDER[@]}"; do
      if [[ "$table" == "IDN_ORG_USER_INVITATION" ]]; then
        DELETE_PROCEDURE+="DELETE FROM $table WHERE INVITED_ORG_ID = '$ORG_UUID';"
      elif [[ "$table" == "IDN_OAUTH_PAR" ]]; then
        DELETE_PROCEDURE+="DELETE FROM $table WHERE EXISTS (SELECT 1 FROM IDN_OAUTH_CONSUMER_APPS WHERE TENANT_ID = $TENANT_ID AND CLIENT_ID = $table.CLIENT_ID);"
      else
        DELETE_PROCEDURE+="DELETE FROM $table WHERE TENANT_ID = $TENANT_ID;"
      fi
    done
    DELETE_PROCEDURE+="COMMIT; SET REFERENTIAL_INTEGRITY TRUE;"

    echo "$DELETE_PROCEDURE" | java -cp "$H2_JAR_PATH" org.h2.tools.Shell -url "$DB_URL" -user "$DB_USER" -password "$DB_PASSWORD" 2>&1 > /tmp/sql_output.log

    if [[ $? -eq 0 ]]; then
      echo "Resources deleted for tenant ID $TENANT_ID with org ID $ORG_UUID." | tee -a "$SUMMARY_FILE"
      echo "$TENANT_ID" >> "$SUCCESSFUL_DELETIONS_FILE"
    else
      FAILED_LOG="$LOG_DIR/failed_tenant_${TENANT_ID}.log"
      mv /tmp/sql_output.log "$FAILED_LOG"
      echo "Failed to process tenant ID $TENANT_ID with org ID $ORG_UUID. Check log: $FAILED_LOG" | tee -a "$SUMMARY_FILE"
    fi

    rm -f /tmp/sql_output.log
  else
    echo "Skipping invalid or empty line: TENANT_ID=$TENANT_ID, ORG_UUID=$ORG_UUID"
  fi
done < "$EXPORT_FILE"

echo "Data deletion process completed. Summary available at $SUMMARY_FILE."

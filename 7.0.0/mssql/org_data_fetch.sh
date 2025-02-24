#!/bin/bash

# Arguments: host port db_name user password batch_size export_file
DB_HOST="$1"
DB_PORT="$2"
DB_NAME="$3"
DB_USER="$4"
DB_PASSWORD="$5"
BATCH_SIZE="$6"
EXPORT_FILE="$7"

# Construct the server connection string
DB_SERVER="${DB_HOST},${DB_PORT}"

echo "DB_SERVER: $DB_SERVER"
echo "DB_NAME: $DB_NAME"
echo "BATCH_SIZE: $BATCH_SIZE"
echo "EXPORT_FILE: $EXPORT_FILE"

# Query to fetch N deleted organizations
FETCH_QUERY="
SET NOCOUNT ON;
SELECT TOP ($BATCH_SIZE) UM_TENANT.UM_ID, UM_TENANT.UM_ORG_UUID
FROM UM_TENANT
LEFT JOIN UM_ORG ON UM_TENANT.UM_ORG_UUID = UM_ORG.UM_ID
WHERE UM_TENANT.UM_ACTIVE = 0 AND UM_ORG.UM_ID IS NULL
ORDER BY UM_TENANT.UM_CREATED_DATE DESC;
"

echo "Fetching tenant IDs and organization UUIDs from MSSQL database..."

# Execute the query and capture output
OUTPUT=$(sqlcmd -S "$DB_SERVER" -d "$DB_NAME" -U "$DB_USER" -P "$DB_PASSWORD" -Q "$FETCH_QUERY" -s "," -W 2>&1)

# Check for actual execution errors
if [[ $? -ne 0 ]]; then
  echo "Failed to fetch data. Please check the database connection and query."
  echo "sqlcmd output: $OUTPUT"
  exit 1
fi

# Process the output
echo "$OUTPUT" | grep -E '^[0-9]+' > "$EXPORT_FILE"

# Check if the export file is empty
if [[ ! -s "$EXPORT_FILE" ]]; then
  echo "Query executed successfully but no data returned. Exiting with success."
  exit 0
else
  echo "Data exported to $EXPORT_FILE successfully."
fi

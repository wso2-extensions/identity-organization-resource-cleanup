#!/bin/bash

# Arguments: host port db_name user password batch_size export_file
DB_HOST="$1"
DB_PORT="$2"
DB_NAME="$3"
DB_USER="$4"
DB_PASSWORD="$5"
BATCH_SIZE="$6"
EXPORT_FILE="$7"

export MYSQL_PWD="$DB_PASSWORD"

# Display configuration
echo "DB_SERVER: ${DB_HOST}:${DB_PORT}"
echo "DB_NAME: $DB_NAME"
echo "BATCH_SIZE: $BATCH_SIZE"
echo "EXPORT_FILE: $EXPORT_FILE"

# Query to fetch N deleted organizations
FETCH_QUERY="
SELECT UM_TENANT.UM_ID AS TENANT_ID, UM_TENANT.UM_ORG_UUID AS ORG_UUID
FROM UM_TENANT
LEFT JOIN UM_ORG ON UM_TENANT.UM_ORG_UUID = UM_ORG.UM_ID
WHERE UM_TENANT.UM_ACTIVE = 0 AND UM_ORG.UM_ID IS NULL
ORDER BY UM_TENANT.UM_CREATED_DATE DESC
LIMIT $BATCH_SIZE;
"

echo "Fetching tenant IDs and organization UUIDs from MySQL database..."

# Temporary file to store raw output
RAW_OUTPUT="/tmp/raw_output.log"

# Execute the query and capture output in a raw format
mysql -h "$DB_HOST" -P "$DB_PORT" -D "$DB_NAME" -u "$DB_USER" -e "$FETCH_QUERY" --batch --silent -r 2>error.log > "$RAW_OUTPUT"

# Check for errors
if [[ $? -ne 0 ]]; then
  echo "Failed to fetch data. MySQL error log:"
  cat error.log
  exit 1
fi

> "$EXPORT_FILE" # Clear previous data.
if [[ ! -s "$RAW_OUTPUT" ]]; then
  echo "Query executed successfully but no data returned. Exiting with success."
  > "$EXPORT_FILE"
  exit 0
  exit 0
fi

# Add header to the output file
# echo "TENANT_ID,ORG_UUID" > "$EXPORT_FILE"

# Process raw output: Convert spaces to commas and write to the final file
while IFS=$'\t' read -r TENANT_ID ORG_UUID; do
  # Skip empty lines
  [[ -z "$TENANT_ID" ]] && continue

  # Write processed line to the export file
  echo "$TENANT_ID,$ORG_UUID" >> "$EXPORT_FILE"
done < "$RAW_OUTPUT"

# Clean up temporary raw output file
rm -f "$RAW_OUTPUT"

# Check if the export file contains more than just the header
if [[ $(wc -l < "$EXPORT_FILE") -le 1 ]]; then
  echo "Query executed successfully but no data returned. Exiting with success."
  exit 0
else
  echo "Data exported to $EXPORT_FILE successfully in CSV format."
fi

# Unset MYSQL_PWD to avoid leaving it in the environment.
unset MYSQL_PWD

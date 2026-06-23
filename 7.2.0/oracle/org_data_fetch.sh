#!/bin/bash

# Arguments: host port db_name user password batch_size export_file
DB_HOST="$1"
DB_PORT="$2"
DB_NAME="$3"
DB_USER="$4"
DB_PASSWORD="$5"
BATCH_SIZE="$6"
EXPORT_FILE="$7"

# Display configuration
echo "DB_SERVER: ${DB_HOST}:${DB_PORT}"
echo "DB_NAME: $DB_NAME"
echo "BATCH_SIZE: $BATCH_SIZE"
echo "EXPORT_FILE: $EXPORT_FILE"

# Query to fetch N deleted organizations
FETCH_QUERY="
SELECT TENANT_ID, ORG_UUID FROM (
  SELECT UM_TENANT.UM_ID AS TENANT_ID, UM_TENANT.UM_ORG_UUID AS ORG_UUID
  FROM UM_TENANT
  LEFT JOIN UM_ORG ON UM_TENANT.UM_ORG_UUID = UM_ORG.UM_ID
  WHERE UM_TENANT.UM_ACTIVE = 0 AND UM_ORG.UM_ID IS NULL
  ORDER BY UM_TENANT.UM_CREATED_DATE DESC
) WHERE ROWNUM <= $BATCH_SIZE;
"

echo "Fetching tenant IDs and organization UUIDs from Oracle database..."

# Temporary file to store raw output
RAW_OUTPUT="/tmp/raw_output.log"

# Execute the query and capture output in a raw format
echo "SET HEAD OFF; SET FEEDBACK OFF; SET PAGESIZE 0; $FETCH_QUERY" | sqlplus -s "$DB_USER/$DB_PASSWORD@//$DB_HOST:$DB_PORT/$DB_NAME" 2>error.log > "$RAW_OUTPUT"

# Check for errors
if [[ $? -ne 0 ]]; then
  echo "Failed to fetch data. Oracle error log:"
  cat error.log
  exit 1
fi

> "$EXPORT_FILE" # Clear previous data.
if [[ ! -s "$RAW_OUTPUT" ]]; then
  echo "Query executed successfully but no data returned. Exiting with success."
  > "$EXPORT_FILE"
  exit 0
fi

# Add header to the output file
# echo "TENANT_ID,ORG_UUID" > "$EXPORT_FILE"

# Process raw output: Convert spaces to commas and write to the final file
while read -r line; do
  # Skip empty lines
  [[ -z "$line" ]] && continue
  
  # Split by whitespace and format as CSV
  TENANT_ID=$(echo "$line" | awk '{print $1}')
  ORG_UUID=$(echo "$line" | awk '{print $2}')
  
  # Skip if either field is empty
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

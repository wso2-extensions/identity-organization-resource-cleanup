#!/bin/bash

# Define database credentials
DB_URL="$1"
DB_USER="$2"
DB_PASSWORD="$3"
BATCH_SIZE="$4"
H2_JAR_PATH="$5"
EXPORT_FILE="$6"

echo "DB_URL: $DB_URL"
echo "BATCH_SIZE: $BATCH_SIZE"
echo "H2_JAR_PATH: $H2_JAR_PATH"

# Query to fetch N deleted organizations
FETCH_QUERY="SELECT UM_TENANT.UM_ID, UM_TENANT.UM_ORG_UUID FROM UM_TENANT LEFT JOIN UM_ORG ON UM_TENANT.UM_ORG_UUID = UM_ORG.UM_ID 
WHERE UM_TENANT.UM_ACTIVE = FALSE AND UM_ORG.UM_ID IS NULL ORDER BY UM_TENANT.UM_CREATED_DATE DESC LIMIT $BATCH_SIZE;"

# Step 1: Fetch data and store in a file
echo "Fetching tenant IDs and organization UUIDs..."
java -cp "$H2_JAR_PATH" org.h2.tools.Shell -url "$DB_URL" -user "$DB_USER" -password "$DB_PASSWORD" \
-sql "$FETCH_QUERY" | grep -E '^[0-9]+' | awk -F'\|' '{print $1 "," $2}' > "$EXPORT_FILE"

# Validate output
if [[ $? -ne 0 ]]; then
  echo "Failed to fetch data. Please check the database connection and query."
  exit 1
fi

# Check if the export file is empty
if [[ ! -s "$EXPORT_FILE" ]]; then
  echo "No data returned from query. Exiting with success."
  exit 0
else
  echo "Data exported to $EXPORT_FILE successfully."
fi

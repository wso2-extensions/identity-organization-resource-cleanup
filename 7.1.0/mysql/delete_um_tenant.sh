#!/bin/bash

# Arguments: DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD SHARED_DB_SUCCESS_FILE IDENTITY_DB_SUCCESS_FILE LOG_DIR
DB_HOST="$1"
DB_PORT="$2"
DB_NAME="$3"
DB_USER="$4"
DB_PASSWORD="$5"
SHARED_DB_SUCCESS_FILE="$6"
IDENTITY_DB_SUCCESS_FILE="$7"
LOG_DIR="$8"

# Export MySQL password to suppress password warnings
export MYSQL_PWD="$DB_PASSWORD"

SUMMARY_FILE="$LOG_DIR/um_tenant_deletion_summary.log"
FAILED_LOG_DIR="$LOG_DIR/failed_deletions"

# Create necessary directories
mkdir -p "$LOG_DIR"
mkdir -p "$FAILED_LOG_DIR"

# Initialize summary log
echo "Summary of UM_TENANT Deletions:" > "$SUMMARY_FILE"

# Check if the input files exist
if [[ ! -f "$SHARED_DB_SUCCESS_FILE" ]]; then
  echo "Shared DB success file not found: $SHARED_DB_SUCCESS_FILE"
  exit 1
fi

if [[ ! -f "$IDENTITY_DB_SUCCESS_FILE" ]]; then
  echo "Identity DB success file not found: $IDENTITY_DB_SUCCESS_FILE"
  exit 1
fi

# Read tenant IDs from both files (excluding header)
echo "Reading tenant IDs from shared DB and identity DB success files..."
SHARED_TENANTS=$(tail -n +2 "$SHARED_DB_SUCCESS_FILE" | sort)
IDENTITY_TENANTS=$(tail -n +2 "$IDENTITY_DB_SUCCESS_FILE" | sort)

# Find mismatched tenant IDs
SHARED_ONLY=$(comm -23 <(echo "$SHARED_TENANTS") <(echo "$IDENTITY_TENANTS"))
IDENTITY_ONLY=$(comm -13 <(echo "$SHARED_TENANTS") <(echo "$IDENTITY_TENANTS"))

# Check for mismatches
if [[ -n "$SHARED_ONLY" || -n "$IDENTITY_ONLY" ]]; then
  echo "Mismatch detected between shared DB and identity DB success files."
  echo "Tenant IDs present only in shared DB:" >> "$SUMMARY_FILE"
  echo "$SHARED_ONLY" >> "$SUMMARY_FILE"
  echo "Tenant IDs present only in identity DB:" >> "$SUMMARY_FILE"
  echo "$IDENTITY_ONLY" >> "$SUMMARY_FILE"
  exit 2
fi

# Find common tenant IDs
COMMON_TENANTS=$(comm -12 <(echo "$SHARED_TENANTS") <(echo "$IDENTITY_TENANTS"))

if [[ -z "$COMMON_TENANTS" ]]; then
  echo "No common tenant IDs found between shared DB and identity DB."
  exit 0
fi

echo "Starting UM_TENANT deletion process..."
for TENANT_ID in $COMMON_TENANTS; do
  echo "Processing TENANT_ID=$TENANT_ID"

  # Generate the delete procedure
  DELETE_PROCEDURE="DELETE FROM UM_TENANT WHERE UM_ID = ${TENANT_ID};"

  # Execute the delete procedure
  echo "Executing deletion procedure for TENANT_ID=$TENANT_ID..."
  mysql -h "$DB_HOST" -P "$DB_PORT" -D "$DB_NAME" -u "$DB_USER" -e "$DELETE_PROCEDURE" --silent > /dev/null 2>&1

  # Check if the execution was successful
  if [[ $? -eq 0 ]]; then
    echo "Successfully deleted UM_TENANT entry for TENANT_ID=$TENANT_ID." | tee -a "$SUMMARY_FILE"
  else
    FAILED_LOG="$FAILED_LOG_DIR/failed_tenant_${TENANT_ID}.log"
    echo "$DELETE_PROCEDURE" > "$FAILED_LOG"
    echo "Failed to delete UM_TENANT entry for TENANT_ID=$TENANT_ID. Check log: $FAILED_LOG" | tee -a "$SUMMARY_FILE"
  fi
done

# Unset MYSQL_PWD to avoid leaving it in the environment
unset MYSQL_PWD

echo "UM_TENANT deletion process completed. Summary available at $SUMMARY_FILE."

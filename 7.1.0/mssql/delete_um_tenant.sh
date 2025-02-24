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
SHARED_TENANTS=$(tail -n +2 "$SHARED_DB_SUCCESS_FILE")
IDENTITY_TENANTS=$(tail -n +2 "$IDENTITY_DB_SUCCESS_FILE")

# Find mismatched tenant IDs
SHARED_ONLY=$(comm -23 <(echo "$SHARED_TENANTS" | sort) <(echo "$IDENTITY_TENANTS" | sort))
IDENTITY_ONLY=$(comm -13 <(echo "$SHARED_TENANTS" | sort) <(echo "$IDENTITY_TENANTS" | sort))

# Check for mismatches
if [[ -n "$SHARED_ONLY" || -n "$IDENTITY_ONLY" ]]; then
  echo "Mismatch detected between shared DB and identity DB success files."
  
  # Log mismatched tenant IDs
  echo "Tenant IDs present only in shared DB:" >> "$SUMMARY_FILE"
  echo "$SHARED_ONLY" >> "$SUMMARY_FILE"

  echo "Tenant IDs present only in identity DB:" >> "$SUMMARY_FILE"
  echo "$IDENTITY_ONLY" >> "$SUMMARY_FILE"

  # Return error code to stop the main script
  exit 2
fi

# Find common tenant IDs
COMMON_TENANTS=$(comm -12 <(echo "$SHARED_TENANTS" | sort) <(echo "$IDENTITY_TENANTS" | sort))

if [[ -z "$COMMON_TENANTS" ]]; then
  echo "No common tenant IDs found between shared DB and identity DB."
  exit 0
fi

# Construct the server connection string
DB_SERVER="${DB_HOST},${DB_PORT}"

echo $DB_SERVER, $DB_NAME, $DB_USER, $DB_PASSWORD

echo "Starting UM_TENANT deletion process..."
for TENANT_ID in $COMMON_TENANTS; do
  echo "Processing TENANT_ID=$TENANT_ID"

  # Generate the delete query
  {
  echo "BEGIN TRANSACTION;"
  echo "DELETE FROM UM_TENANT WHERE UM_ID = $TENANT_ID;"
  echo "COMMIT;"
  echo "GO"
} | sqlcmd -S "$DB_SERVER" -d "$DB_NAME" -U "$DB_USER" -P "$DB_PASSWORD" -b -m 1 -o "/tmp/sql_output.log"


  # Check if the execution was successful
  if [[ $? -eq 0 ]]; then
    echo "Successfully deleted UM_TENANT entry for TENANT_ID=$TENANT_ID." | tee -a "$SUMMARY_FILE"
  else
    FAILED_LOG="$FAILED_LOG_DIR/failed_tenant_${TENANT_ID}.log"
    mv /tmp/sql_output.log "$FAILED_LOG"
    echo "Failed to delete UM_TENANT entry for TENANT_ID=$TENANT_ID. Check log: $FAILED_LOG" | tee -a "$SUMMARY_FILE"
  fi

  rm -f /tmp/sql_output.log
done

echo "UM_TENANT deletion process completed. Summary available at $SUMMARY_FILE."

#!/bin/bash

# Define database credentials
DB_URL="$1"
DB_USER="$2"
DB_PASSWORD="$3"
H2_JAR_PATH="$4"
SHARED_DB_SUCCESS_FILE="$5"
IDENTITY_DB_SUCCESS_FILE="$6"
LOG_DIR="$7"
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

# Read tenant IDs from both files
echo "Reading tenant IDs from shared DB and identity DB success files..."
SHARED_TENANTS=$(tail -n +2 "$SHARED_DB_SUCCESS_FILE")  # Exclude header
IDENTITY_TENANTS=$(tail -n +2 "$IDENTITY_DB_SUCCESS_FILE")  # Exclude header

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

# Iterate through common tenant IDs and delete them from UM_TENANT
echo "Starting UM_TENANT deletion process..."
for TENANT_ID in $COMMON_TENANTS; do
  echo "Processing TENANT_ID=$TENANT_ID"

  # Generate and execute the delete query
  {
    echo "BEGIN TRANSACTION;"
    echo "DELETE FROM UM_TENANT WHERE UM_ID = $TENANT_ID;"
    echo "COMMIT;"
  } | java -cp "$H2_JAR_PATH" org.h2.tools.Shell -url "$DB_URL" -user "$DB_USER" -password "$DB_PASSWORD" 2>&1 > /tmp/sql_output.log

  # Check if the execution was successful
  if [[ $? -eq 0 ]]; then
    echo "Successfully deleted UM_TENANT entry for TENANT_ID=$TENANT_ID." | tee -a "$SUMMARY_FILE"
  else
    FAILED_LOG="$FAILED_LOG_DIR/failed_tenant_${TENANT_ID}.log"
    mv /tmp/sql_output.log "$FAILED_LOG"
    echo "Failed to delete UM_TENANT entry for TENANT_ID=$TENANT_ID. Check log: $FAILED_LOG" | tee -a "$SUMMARY_FILE"
  fi

  # Clean up temporary files
  rm -f /tmp/sql_output.log
done

echo "UM_TENANT deletion process completed. Summary available at $SUMMARY_FILE."

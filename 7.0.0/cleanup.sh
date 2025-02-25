#!/bin/bash

# ========================================================
# Configuration Section
# ========================================================

# Supported DB types: h2, mssql, mysql
SHARED_DB_TYPE="mysql"     # can be h2, mssql, or mysql
IDENTITY_DB_TYPE="mysql"   # can be h2, mssql, or mysql


# Shared database configurations
SHARED_DB_HOSTS=("127.0.0.1")
SHARED_DB_PORTS=("3307")  # MSSQL default port is 1433; MySQL default is 3306
SHARED_DB_USERS=("root")
SHARED_DB_PASSWORDS=("yourpassword")
SHARED_DB_NAMES=("wso2shared_db")
SHARED_DB_LOG_DIRS=("path/to/shared_db_result_01")

# Identity database configurations
IDENTITY_DB_HOSTS=("127.0.0.1")
IDENTITY_DB_PORTS=("3307")
IDENTITY_DB_USERS=("root")
IDENTITY_DB_PASSWORDS=("yourpassword")
IDENTITY_DB_NAMES=("wso2identity_db")
IDENTITY_DB_LOG_DIRS=("path/to/identity_db_result_01")

# Common credentials (assuming the same user/password for simplicity)

BATCH_SIZE=5
BATCH_WAIT_TIME=5000 # in milliseconds
EXPORT_FILE="path/to/exported/exported_data.csv" 

# H2_JAR_PATH="H2/jar/path" # For MSSQL and MySQL, we do not need external JARs


# ========================================================
# Functions Section
# ========================================================

get_jar_path() {
  local db_type="$1"
  case "$db_type" in
    h2)
      echo "$H2_JAR_PATH"
      ;;
    mssql|mysql)
      # No jar needed for MSSQL or MySQL as per the new requirement
      echo ""
      ;;
    *)
      echo ""
      ;;
  esac
}

# For validation
validate_db_configs() {
  local db_type="$1"
  # If needed, add specific validations. Currently, it's minimal.
}

# Extract parameters based on DB type
# For h2: return URL
# For mssql/mysql: return host, port, db
get_db_params() {
  local db_type="$1"
  local index="$2"
  local mode="$3" # "shared" or "identity"

  if [[ "$mode" == "shared" ]]; then
    local user="${SHARED_DB_USERS[$index]}"
    local password="${SHARED_DB_PASSWORDS[$index]}"
    local log_dir="${SHARED_DB_LOG_DIRS[$index]}"

    if [[ "$db_type" == "h2" ]]; then
      local url="${SHARED_DB_URLS[$index]}"
      echo "$url" "$user" "$password" "$log_dir"
    else
      local host="${SHARED_DB_HOSTS[$index]}"
      local port="${SHARED_DB_PORTS[$index]}"
      local db_name="${SHARED_DB_NAMES[$index]}"
      echo "$host" "$port" "$db_name" "$user" "$password" "$log_dir"
    fi
  else
    # identity DB
    local user="${IDENTITY_DB_USERS[$index]}"
    local password="${IDENTITY_DB_PASSWORDS[$index]}"
    local log_dir="${IDENTITY_DB_LOG_DIRS[$index]}"

    if [[ "$db_type" == "h2" ]]; then
      local url="${IDENTITY_DB_URLS[$index]}"
      echo "$url" "$user" "$password" "$log_dir"
    else
      local host="${IDENTITY_DB_HOSTS[$index]}"
      local port="${IDENTITY_DB_PORTS[$index]}"
      local db_name="${IDENTITY_DB_NAMES[$index]}"
      echo "$host" "$port" "$db_name" "$user" "$password" "$log_dir"
    fi
  fi
}

# Determine arguments for scripts based on DB type:
# H2 scripts: ... URL USER PASSWORD BATCH_SIZE [JAR] EXPORT_FILE
# MSSQL/MySQL scripts: ... HOST PORT DB_NAME USER PASSWORD BATCH_SIZE EXPORT_FILE (no jar)
run_org_data_fetch() {
  local db_type="$1"
  shift
  local script="$1"
  shift
  if [[ "$db_type" == "h2" ]]; then
    local url="$1" user="$2" password="$3" batch="$4" jar="$5" export_file="$6"
    "$script" "$url" "$user" "$password" "$batch" "$jar" "$export_file"
  else
    local host="$1" port="$2" db_name="$3" user="$4" password="$5" batch="$6" export_file="$7"
    "$script" "$host" "$port" "$db_name" "$user" "$password" "$batch" "$export_file"
  fi
}

run_shared_cleanup() {
  local db_type="$1"
  shift
  local script="$1"
  shift
  if [[ "$db_type" == "h2" ]]; then
    local url="$1" user="$2" password="$3" jar="$4" export_file="$5" log_dir="$6"
    "$script" "$url" "$user" "$password" "$jar" "$export_file" "$log_dir"
  else
    local host="$1" port="$2" db_name="$3" user="$4" password="$5" export_file="$6" log_dir="$7"
    "$script" "$host" "$port" "$db_name" "$user" "$password" "$export_file" "$log_dir"
  fi
}

run_identity_cleanup() {
  local db_type="$1"
  shift
  local script="$1"
  shift
  if [[ "$db_type" == "h2" ]]; then
    local url="$1" user="$2" password="$3" jar="$4" export_file="$5" log_dir="$6"
    "$script" "$url" "$user" "$password" "$jar" "$export_file" "$log_dir"
  else
    local host="$1" port="$2" db_name="$3" user="$4" password="$5" export_file="$6" log_dir="$7"
    "$script" "$host" "$port" "$db_name" "$user" "$password" "$export_file" "$log_dir"
  fi
}

run_um_tenant_cleanup() {
  local shared_db_type="$1"
  shift
  local script="$1"
  shift
  if [[ "$shared_db_type" == "h2" ]]; then
    local url="$1" user="$2" password="$3" jar="$4" shared_success_file="$5" identity_success_file="$6" log_dir="$7"
    "$script" "$url" "$user" "$password" "$jar" "$shared_success_file" "$identity_success_file" "$log_dir"
  else
    local host="$1" port="$2" db_name="$3" user="$4" password="$5" shared_success_file="$6" identity_success_file="$7" log_dir="$8"
    "$script" "$host" "$port" "$db_name" "$user" "$password" "$shared_success_file" "$identity_success_file" "$log_dir"
  fi
}

# ========================================================
# Main Execution
# ========================================================

# Validate configurations
validate_db_configs "$SHARED_DB_TYPE" SHARED_DB_URLS[@]
validate_db_configs "$IDENTITY_DB_TYPE" IDENTITY_DB_URLS[@]

PRIMARY_SHARED_INDEX=0
PRIMARY_IDENTITY_INDEX=0

# Extract primary shared DB parameters
PRIMARY_SHARED_PARAMS=($(get_db_params "$SHARED_DB_TYPE" "$PRIMARY_SHARED_INDEX" "shared"))
PRIMARY_IDENTITY_PARAMS=($(get_db_params "$IDENTITY_DB_TYPE" "$PRIMARY_IDENTITY_INDEX" "identity"))

# Assign variables for clarity
if [[ "$SHARED_DB_TYPE" == "h2" ]]; then
  PRIMARY_SHARED_URL="${PRIMARY_SHARED_PARAMS[0]}"
  PRIMARY_SHARED_USER="${PRIMARY_SHARED_PARAMS[1]}"
  PRIMARY_SHARED_PASSWORD="${PRIMARY_SHARED_PARAMS[2]}"
  PRIMARY_SHARED_LOG_DIR="${PRIMARY_SHARED_PARAMS[3]}"
else
  PRIMARY_SHARED_HOST="${PRIMARY_SHARED_PARAMS[0]}"
  PRIMARY_SHARED_PORT="${PRIMARY_SHARED_PARAMS[1]}"
  PRIMARY_SHARED_DB="${PRIMARY_SHARED_PARAMS[2]}"
  PRIMARY_SHARED_USER="${PRIMARY_SHARED_PARAMS[3]}"
  PRIMARY_SHARED_PASSWORD="${PRIMARY_SHARED_PARAMS[4]}"
  PRIMARY_SHARED_LOG_DIR="${PRIMARY_SHARED_PARAMS[5]}"
fi

if [[ "$IDENTITY_DB_TYPE" == "h2" ]]; then
  PRIMARY_IDENTITY_URL="${PRIMARY_IDENTITY_PARAMS[0]}"
  PRIMARY_IDENTITY_USER="${PRIMARY_IDENTITY_PARAMS[1]}"
  PRIMARY_IDENTITY_PASSWORD="${PRIMARY_IDENTITY_PARAMS[2]}"
  PRIMARY_IDENTITY_LOG_DIR="${PRIMARY_IDENTITY_PARAMS[3]}"
else
  PRIMARY_IDENTITY_HOST="${PRIMARY_IDENTITY_PARAMS[0]}"
  PRIMARY_IDENTITY_PORT="${PRIMARY_IDENTITY_PARAMS[1]}"
  PRIMARY_IDENTITY_DB="${PRIMARY_IDENTITY_PARAMS[2]}"
  PRIMARY_IDENTITY_USER="${PRIMARY_IDENTITY_PARAMS[3]}"
  PRIMARY_IDENTITY_PASSWORD="${PRIMARY_IDENTITY_PARAMS[4]}"
  PRIMARY_IDENTITY_LOG_DIR="${PRIMARY_IDENTITY_PARAMS[5]}"
fi

SHARED_DB_JAR=$(get_jar_path "$SHARED_DB_TYPE")
IDENTITY_DB_JAR=$(get_jar_path "$IDENTITY_DB_TYPE")

while true; do
  # --------------------------------------------------------
  # Step 1: Fetch deleted organization data
  # --------------------------------------------------------
  DATA_FETCH_SCRIPT="./${SHARED_DB_TYPE}/org_data_fetch.sh"
  if [[ ! -f "$DATA_FETCH_SCRIPT" ]]; then
    echo "Error: Data fetch script for type '$SHARED_DB_TYPE' not found. Exiting."
    exit 1
  fi

  echo "Fetching up to $BATCH_SIZE deleted organization data..."
  if [[ "$SHARED_DB_TYPE" == "h2" ]]; then
    run_org_data_fetch "$SHARED_DB_TYPE" "$DATA_FETCH_SCRIPT" \
      "$PRIMARY_SHARED_URL" "$PRIMARY_SHARED_USER" "$PRIMARY_SHARED_PASSWORD" \
      "$BATCH_SIZE" "$SHARED_DB_JAR" "$EXPORT_FILE"
  else
    run_org_data_fetch "$SHARED_DB_TYPE" "$DATA_FETCH_SCRIPT" \
      "$PRIMARY_SHARED_HOST" "$PRIMARY_SHARED_PORT" "$PRIMARY_SHARED_DB" \
      "$PRIMARY_SHARED_USER" "$PRIMARY_SHARED_PASSWORD" "$BATCH_SIZE" "$EXPORT_FILE"
  fi

  if [[ $? -ne 0 ]]; then
    echo "Failed to fetch deleted organization data. Exiting."
    exit 1
  fi

  # Check if the export file is empty
  if [[ ! -s "$EXPORT_FILE" ]]; then
    echo "No more data to process. Exiting the loop."
    break
  fi

  # --------------------------------------------------------
  # Step 2: Clean shared DB resources
  # --------------------------------------------------------
  SHARED_CLEANUP_SCRIPT="./${SHARED_DB_TYPE}/shared_db_cleanup.sh"
  if [[ ! -f "$SHARED_CLEANUP_SCRIPT" ]]; then
    echo "Error: Shared DB cleanup script for type '$SHARED_DB_TYPE' not found. Exiting."
    exit 1
  fi

  for (( i=0; i<${#SHARED_DB_USERS[@]}; i++ )); do
    SHARED_PARAMS=($(get_db_params "$SHARED_DB_TYPE" "$i" "shared"))

    if [[ "$SHARED_DB_TYPE" == "h2" ]]; then
      run_shared_cleanup "$SHARED_DB_TYPE" "$SHARED_CLEANUP_SCRIPT" \
        "${SHARED_PARAMS[0]}" "${SHARED_PARAMS[1]}" "${SHARED_PARAMS[2]}" \
        "$SHARED_DB_JAR" "$EXPORT_FILE" "${SHARED_PARAMS[3]}"
    else
      run_shared_cleanup "$SHARED_DB_TYPE" "$SHARED_CLEANUP_SCRIPT" \
        "${SHARED_PARAMS[0]}" "${SHARED_PARAMS[1]}" "${SHARED_PARAMS[2]}" \
        "${SHARED_PARAMS[3]}" "${SHARED_PARAMS[4]}" "$EXPORT_FILE" "${SHARED_PARAMS[5]}"
    fi

    if [[ $? -ne 0 ]]; then
      echo "Failed to clean shared DB resources for shared DB index $i. Exiting."
      exit 1
    fi
  done

  # --------------------------------------------------------
  # Step 3: Clean identity DB resources
  # --------------------------------------------------------
  IDENTITY_CLEANUP_SCRIPT="./${IDENTITY_DB_TYPE}/identity_db_cleanup.sh"
  if [[ ! -f "$IDENTITY_CLEANUP_SCRIPT" ]]; then
    echo "Error: Identity DB cleanup script for type '$IDENTITY_DB_TYPE' not found. Exiting."
    exit 1
  fi

  for (( j=0; j<${#IDENTITY_DB_USERS[@]}; j++ )); do
  echo "Processing identity DB index $j..."
    IDENTITY_PARAMS=($(get_db_params "$IDENTITY_DB_TYPE" "$j" "identity"))

    if [[ "$IDENTITY_DB_TYPE" == "h2" ]]; then
      run_identity_cleanup "$IDENTITY_DB_TYPE" "$IDENTITY_CLEANUP_SCRIPT" \
        "${IDENTITY_PARAMS[0]}" "${IDENTITY_PARAMS[1]}" "${IDENTITY_PARAMS[2]}" \
        "$IDENTITY_DB_JAR" "$EXPORT_FILE" "${IDENTITY_PARAMS[3]}"
    else
      run_identity_cleanup "$IDENTITY_DB_TYPE" "$IDENTITY_CLEANUP_SCRIPT" \
        "${IDENTITY_PARAMS[0]}" "${IDENTITY_PARAMS[1]}" "${IDENTITY_PARAMS[2]}" \
        "${IDENTITY_PARAMS[3]}" "${IDENTITY_PARAMS[4]}" "$EXPORT_FILE" "${IDENTITY_PARAMS[5]}"
    fi

    if [[ $? -ne 0 ]]; then
      echo "Failed to clean identity DB resources for identity DB index $j. Exiting."
      exit 1
    fi
  done

  # --------------------------------------------------------
  # Step 4: Check tenant mismatches and clean tenant information
  # --------------------------------------------------------
  DELETE_UM_TENANT_SCRIPT="./${SHARED_DB_TYPE}/delete_um_tenant.sh"
  if [[ ! -f "$DELETE_UM_TENANT_SCRIPT" ]]; then
    echo "Error: UM_TENANT cleanup script for type '$SHARED_DB_TYPE' not found. Exiting."
    exit 1
  fi

  SHARED_DB_SUCCESS_FILE_PATH="${PRIMARY_SHARED_LOG_DIR}/successful_deletions.csv"
  IDENTITY_DB_SUCCESS_FILE_PATH="${PRIMARY_IDENTITY_LOG_DIR}/successful_deletions.csv"

  echo "Cleaning tenant information using $DELETE_UM_TENANT_SCRIPT..."
  if [[ "$SHARED_DB_TYPE" == "h2" ]]; then
    run_um_tenant_cleanup "$SHARED_DB_TYPE" "$DELETE_UM_TENANT_SCRIPT" \
      "$PRIMARY_SHARED_URL" "$PRIMARY_SHARED_USER" "$PRIMARY_SHARED_PASSWORD" \
      "$SHARED_DB_JAR" "$SHARED_DB_SUCCESS_FILE_PATH" "$IDENTITY_DB_SUCCESS_FILE_PATH" "$PRIMARY_SHARED_LOG_DIR"
  else
    run_um_tenant_cleanup "$SHARED_DB_TYPE" "$DELETE_UM_TENANT_SCRIPT" \
      "$PRIMARY_SHARED_HOST" "$PRIMARY_SHARED_PORT" "$PRIMARY_SHARED_DB" \
      "$PRIMARY_SHARED_USER" "$PRIMARY_SHARED_PASSWORD" \
      "$SHARED_DB_SUCCESS_FILE_PATH" "$IDENTITY_DB_SUCCESS_FILE_PATH" "$PRIMARY_SHARED_LOG_DIR"
  fi

  if [[ $? -ne 0 ]]; then
    echo "Failed to clean UM_TENANT information. Exiting."
    exit 1
  fi

  echo "Batch processing completed. Waiting $BATCH_WAIT_TIME milliseconds before resuming."
  sleep $(bc <<< "scale=2; $BATCH_WAIT_TIME/1000")
done

echo "Cleanup process completed successfully."

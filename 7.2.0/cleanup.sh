#!/bin/bash

# ========================================================
# Configuration Section
# ========================================================

# Supported DB types: h2, mssql, mysql, postgresql
SHARED_DB_TYPE="mysql"     # can be h2, mssql, postgresql or mysql
IDENTITY_DB_TYPE="mysql"   # can be h2, mssql, postgresql or mysql


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

ensure_bc() {
  if command -v bc >/dev/null 2>&1; then
    return 0
  fi

  echo "'bc' is required for the batch wait time but is not installed. Installing it..."

  if command -v apt-get >/dev/null 2>&1; then
    if ! run_privileged apt-get update || ! run_privileged apt-get install -y bc; then
      echo "Error: failed to install 'bc' with apt-get."
      return 1
    fi
  elif command -v apk >/dev/null 2>&1; then
    if ! run_privileged apk add --no-cache bc; then
      echo "Error: failed to install 'bc' with apk."
      return 1
    fi
  elif command -v dnf >/dev/null 2>&1; then
    if ! run_privileged dnf install -y bc; then
      echo "Error: failed to install 'bc' with dnf."
      return 1
    fi
  elif command -v yum >/dev/null 2>&1; then
    if ! run_privileged yum install -y bc; then
      echo "Error: failed to install 'bc' with yum."
      return 1
    fi
  else
    echo "Error: 'bc' is not installed and no supported package manager was found. Install 'bc' manually."
    return 1
  fi

  if ! command -v bc >/dev/null 2>&1; then
    echo "Error: failed to install 'bc'."
    return 1
  fi
}

run_privileged() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "Error: 'bc' is not installed and this user cannot install packages. Run as root or install 'bc' manually."
    return 1
  fi
}

# For validation
validate_db_configs() {
  local db_type="$1"
  local mode="$2"
  local expected_length
  local index
  local -a array_names array_lengths

  if [[ "$db_type" != "h2" && "$db_type" != "mssql" && "$db_type" != "mysql" && "$db_type" != "postgresql" ]]; then
    echo "Error: unsupported $mode database type '$db_type'."
    return 1
  fi

  if [[ "$mode" == "shared" ]]; then
    if [[ "$db_type" == "h2" ]]; then
      array_names=("SHARED_DB_URLS" "SHARED_DB_USERS" "SHARED_DB_PASSWORDS" "SHARED_DB_LOG_DIRS")
      array_lengths=("${#SHARED_DB_URLS[@]}" "${#SHARED_DB_USERS[@]}" "${#SHARED_DB_PASSWORDS[@]}" "${#SHARED_DB_LOG_DIRS[@]}")
    else
      array_names=("SHARED_DB_HOSTS" "SHARED_DB_PORTS" "SHARED_DB_NAMES" "SHARED_DB_USERS" "SHARED_DB_PASSWORDS" "SHARED_DB_LOG_DIRS")
      array_lengths=("${#SHARED_DB_HOSTS[@]}" "${#SHARED_DB_PORTS[@]}" "${#SHARED_DB_NAMES[@]}" "${#SHARED_DB_USERS[@]}" "${#SHARED_DB_PASSWORDS[@]}" "${#SHARED_DB_LOG_DIRS[@]}")
    fi
  elif [[ "$mode" == "identity" ]]; then
    if [[ "$db_type" == "h2" ]]; then
      array_names=("IDENTITY_DB_URLS" "IDENTITY_DB_USERS" "IDENTITY_DB_PASSWORDS" "IDENTITY_DB_LOG_DIRS")
      array_lengths=("${#IDENTITY_DB_URLS[@]}" "${#IDENTITY_DB_USERS[@]}" "${#IDENTITY_DB_PASSWORDS[@]}" "${#IDENTITY_DB_LOG_DIRS[@]}")
    else
      array_names=("IDENTITY_DB_HOSTS" "IDENTITY_DB_PORTS" "IDENTITY_DB_NAMES" "IDENTITY_DB_USERS" "IDENTITY_DB_PASSWORDS" "IDENTITY_DB_LOG_DIRS")
      array_lengths=("${#IDENTITY_DB_HOSTS[@]}" "${#IDENTITY_DB_PORTS[@]}" "${#IDENTITY_DB_NAMES[@]}" "${#IDENTITY_DB_USERS[@]}" "${#IDENTITY_DB_PASSWORDS[@]}" "${#IDENTITY_DB_LOG_DIRS[@]}")
    fi
  else
    echo "Error: unknown database configuration mode '$mode'."
    return 1
  fi

  expected_length="${array_lengths[0]}"
  if [[ "$expected_length" -eq 0 ]]; then
    echo "Error: $mode database configuration cannot be empty."
    return 1
  fi

  for ((index = 1; index < ${#array_lengths[@]}; index++)); do
    if [[ "${array_lengths[$index]}" -ne "$expected_length" ]]; then
      echo "Error: $mode database configuration length mismatch: ${array_names[0]} has $expected_length entries, but ${array_names[$index]} has ${array_lengths[$index]}."
      return 1
    fi
  done
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
      printf '%s\n' "$url" "$user" "$password" "$log_dir"
    else
      local host="${SHARED_DB_HOSTS[$index]}"
      local port="${SHARED_DB_PORTS[$index]}"
      local db_name="${SHARED_DB_NAMES[$index]}"
      printf '%s\n' "$host" "$port" "$db_name" "$user" "$password" "$log_dir"
    fi
  else
    # identity DB
    local user="${IDENTITY_DB_USERS[$index]}"
    local password="${IDENTITY_DB_PASSWORDS[$index]}"
    local log_dir="${IDENTITY_DB_LOG_DIRS[$index]}"

    if [[ "$db_type" == "h2" ]]; then
      local url="${IDENTITY_DB_URLS[$index]}"
      printf '%s\n' "$url" "$user" "$password" "$log_dir"
    else
      local host="${IDENTITY_DB_HOSTS[$index]}"
      local port="${IDENTITY_DB_PORTS[$index]}"
      local db_name="${IDENTITY_DB_NAMES[$index]}"
      printf '%s\n' "$host" "$port" "$db_name" "$user" "$password" "$log_dir"
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

validate_cleanup_success_file() {
  local log_dir="$1"
  local database_label="$2"
  local index="$3"
  local success_file="$log_dir/successful_deletions.csv"
  local expected_tenants successful_tenants

  if [[ ! -f "$success_file" ]]; then
    echo "Error: $database_label index $index did not produce $success_file."
    return 1
  fi

  expected_tenants=$(awk -F',' 'NF >= 2 && $1 != "TENANT_ID" { print $1 }' "$EXPORT_FILE" | sort -u)
  successful_tenants=$(tail -n +2 "$success_file" | sort -u)
  if [[ "$expected_tenants" != "$successful_tenants" ]]; then
    echo "Error: $database_label index $index did not successfully clean every exported tenant."
    return 1
  fi
}

# ========================================================
# Main Execution
# ========================================================

# Validate configurations
validate_db_configs "$SHARED_DB_TYPE" "shared" || exit 1
validate_db_configs "$IDENTITY_DB_TYPE" "identity" || exit 1

PRIMARY_SHARED_INDEX=0
PRIMARY_IDENTITY_INDEX=0

# Extract primary shared DB parameters
IFS=$'\n' read -r -d '' -a PRIMARY_SHARED_PARAMS < <(get_db_params "$SHARED_DB_TYPE" "$PRIMARY_SHARED_INDEX" "shared"; printf '\0')
IFS=$'\n' read -r -d '' -a PRIMARY_IDENTITY_PARAMS < <(get_db_params "$IDENTITY_DB_TYPE" "$PRIMARY_IDENTITY_INDEX" "identity"; printf '\0')

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
    IFS=$'\n' read -r -d '' -a SHARED_PARAMS < <(get_db_params "$SHARED_DB_TYPE" "$i" "shared"; printf '\0')

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

    validate_cleanup_success_file "${SHARED_DB_LOG_DIRS[$i]}" "shared DB" "$i" || exit 1
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
    IFS=$'\n' read -r -d '' -a IDENTITY_PARAMS < <(get_db_params "$IDENTITY_DB_TYPE" "$j" "identity"; printf '\0')

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

    validate_cleanup_success_file "${IDENTITY_DB_LOG_DIRS[$j]}" "identity DB" "$j" || exit 1
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
  ensure_bc || exit 1
  sleep $(bc <<< "scale=2; $BATCH_WAIT_TIME/1000")
done

echo "Cleanup process completed successfully."

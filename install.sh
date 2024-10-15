#!/usr/bin/env bash
set -o nounset
set -o pipefail

create_immich_directory() {
  local -r Tgt='./immich-app'
  echo "Creating Immich directory..."
  if [[ -e $Tgt ]]; then
    echo "Found existing directory $Tgt, will overwrite YAML files"
  else
    mkdir "$Tgt" || return
  fi
  cd "$Tgt" || return 1
}

download_file() {
  local file="$1"
  local renamed_file="$2"

  if [[ -z "$renamed_file" ]]; then
    renamed_file="$file"
  fi

  echo "  Downloading $file..."
  if "${Curl[@]}" "$RepoUrl/$file" -o "./$renamed_file"; then
    return 0  # Success (true)
  else
    return 1  # Failure (false)
  fi
}

generate_random_db_password(){
  echo "  Generate random password for .env file..."
  rand_pass=$(generate_random_password 10)
  sed -i -e "s/DB_PASSWORD=postgres/DB_PASSWORD=${rand_pass}/" ./.env
}

start_docker_compose() {
  echo "Starting Immich's docker containers"
  mkdir -p ./postgres ./library

  # Set the compose command based on availability
  if docker compose >/dev/null 2>&1; then
    compose_cmd="docker compose"
  elif docker-compose >/dev/null 2>&1; then
    compose_cmd="docker-compose"
  else
    echo "Neither docker compose nor docker-compose is available."
    return 1
  fi

  # Try to bring up the containers
  if ! $compose_cmd up --remove-orphans -d; then
    echo "Could not start with $compose_cmd. Checking for start_interval issue..."

    # Remove start_interval from the docker-compose.yml
    sed -i '/start_interval/d' docker-compose.yml

    # Try to bring up the containers again
    if ! $compose_cmd up --remove-orphans -d; then
      echo "Could not start with $compose_cmd after removing start_interval. Check for errors above."
      return 1
    fi
  fi

  
  show_friendly_message
}

show_friendly_message() {
  local ip_address
  ip_address=$(hostname -I | sed -e 's/ .*//')
  cat <<EOF
Successfully deployed Immich!
You can access the website at http://$ip_address:2283 and the server URL for the mobile app is http://$ip_address:2283/api
---------------------------------------------------
If you want to configure custom information of the server, including the database, Redis information, or the backup (or upload) location, etc.

  1. First bring down the containers with the command 'docker compose down' in the immich-app directory,

  2. Then change the information that fits your needs in the '.env' file,

  3. Finally, bring the containers back up with the command 'docker compose up --remove-orphans -d' in the immich-app directory
EOF
}

generate_random_password() {
  local length="$1"
  local rand_pass=$(echo "$RANDOM$(date)$RANDOM" | sha256sum | base64 | head -c"$length")
  if [ -z "$rand_pass" ]; then
    echo "${RANDOM}${RANDOM}"
  else
    echo "${rand_pass}"
  fi
}

set_backups() {
  echo "Setting up backups..."

    sed -i '/^services:/a\
  backup:\
    container_name: immich_db_dumper\
    image: prodrigestivill/postgres-backup-local:14\
    restart: always\
    env_file:\
      - .env\
    environment:\
      POSTGRES_HOST: database\
      POSTGRES_CLUSTER: '\''TRUE'\''\
      POSTGRES_USER: ${DB_USERNAME}\
      POSTGRES_PASSWORD: ${DB_PASSWORD}\
      POSTGRES_DB: ${DB_DATABASE_NAME}\
      SCHEDULE: "@daily"\
      POSTGRES_EXTRA_OPTS: '\''--clean --if-exists'\''\
      BACKUP_DIR: /db_dumps\
    volumes:\
      - ./db_dumps:/db_dumps\
    depends_on:\
      - database\
      ' docker-compose.yml

  mkdir -p ./db_dumps
}

hw_is_wsl() {
  # Check if running in WSL by looking for WSL-specific files
  if grep -q "Microsoft" /proc/version || [ -f /proc/sys/kernel/osrelease ] && grep -q "WSL" /proc/sys/kernel/osrelease; then
    echo "WSL detected."
    return 0  # True (running in WSL)
  else
    return 1  # False (not running in WSL)
  fi
}

hwa_is_cuda() {
  # Check for NVIDIA GPU, drivers, and CUDA toolkit
  if command -v lspci > /dev/null 2>&1; then
    if lspci | grep -i nvidia > /dev/null 2>&1; then
      # NVIDIA GPU detected
      
      # Use command -v to check for nvidia-smi and nvcc safely
      if command -v nvidia-smi > /dev/null 2>&1 && command -v nvcc > /dev/null 2>&1; then
        # NVIDIA drivers and CUDA toolkit are installed
        echo "Hardware Acceleration: Cuda Detected"
        return 0  # True (CUDA available)
      fi
    fi
  fi
  
  return 1  # False (CUDA not available)
}

hwa_is_armnn() {
  # Check for ARM architecture
  if [[ $(uname -m) == "arm"* || $(uname -m) == "aarch64" ]]; then

    # Check for specific instruction sets (e.g., NEON)
    if grep -q "neon" /proc/cpuinfo; then
      echo "Hardware Acceleration: Arm NN Detected"
      return 0  # True (Arm NN compatible)
    fi
  fi
  return 1  # False (not Arm NN compatible)
}

hwa_is_openvino() {
  # Check for Intel CPU
  if grep -q "GenuineIntel" /proc/cpuinfo; then
    # Intel CPU detected
    
    # Check for AVX2 support
    if grep -q "avx2" /proc/cpuinfo; then
      # AVX2 is supported
      echo "Hardware Acceleration: OpenVINO Detected"
      return 0  # True (compatible)
    fi

    # Check for AVX512 support
    if grep -q "avx512" /proc/cpuinfo; then
      # AVX512 is supported
      echo "Hardware Acceleration: OpenVINO Detected"
      return 0  # True (compatible)
    fi
  fi
  return 1  # False (not compatible)
}

hwt_is_nvec() {
  # Check for NVIDIA GPU and NVENC support
  if command -v lspci > /dev/null 2>&1; then
    if lspci | grep -i nvidia > /dev/null 2>&1; then
      # NVIDIA GPU detected
      
      # Check if nvidia-smi is available
      if command -v nvidia-smi > /dev/null 2>&1; then
        # Get the GPU information
        local gpu_info=$(nvidia-smi --query-gpu=name --format=csv,noheader)
        
        # Check if NVENC is supported (can be adjusted based on GPU model)
        if nvidia-smi -q -d SUPPORTED_CLOCKS | grep -i "NVENC" > /dev/null 2>&1; then
          # NVENC is available for use
          echo "Hardware Transcoding: NVENC Detected"
          return 0  # True (NVENC available)
        fi
      fi
    fi
  fi
  return 1  # False (NVENC not available)
}

hwt_is_quicksync() {
  # Check if lscpu is available
  if command -v lscpu > /dev/null 2>&1; then
    # Check for Intel CPU
    if lscpu | grep -i "Intel" > /dev/null 2>&1; then
      # Intel CPU detected

      # Check if the CPU supports Quick Sync
      if lscpu | grep -q "avx" && lscpu | grep -q "sse"; then
        # Check if the necessary video drivers are loaded
        if command -v vainfo > /dev/null 2>&1; then
          local quick_sync_support=$(vainfo | grep -i "h264")

          if [[ -n $quick_sync_support ]]; then
            echo "Hardware Transcoding: Quick Sync Detected"
            return 0  # True (Quick Sync available)
          fi
        fi
      fi
    fi
  fi
  return 1  # False (Quick Sync not available)
}

hwt_is_rkmpp() {
  # Check for Rockchip hardware
  if command -v lspci > /dev/null 2>&1; then
    if lspci | grep -i "rockchip" > /dev/null 2>&1; then
      # Rockchip hardware detected

      # Check if the necessary drivers are loaded
      if command -v rkmpp > /dev/null 2>&1; then
        local rkmpp_support=$(rkmpp -version)

        if [[ -n $rkmpp_support ]]; then
          echo "Hardware Transcoding: RKMPP Detected"
          return 0  # True (RKMMP available)
        fi
      fi
    fi
  fi
  return 1  # False (RKMMP not available)
}

hwt_is_vaapi() {
  # Check for VAAPI support
  if command -v vainfo > /dev/null 2>&1; then
    # VAAPI command found, check for hardware support
    local vaapi_support=$(vainfo)

    if [[ $vaapi_support == *"driver:"* ]]; then
      echo "Hardware Transcoding: VAAPI Detected"
      return 0  # True (VAAPI available)
    fi
  fi
  return 1  # False (VAAPI not available)
}

merge_extends() {
  local compose_file="$1"
  local extends_file="$2"
  local service_name="$3"
  local image_flag="$4"
  local hw_flag="$image_flag"
  local extends_content=$(< "$extends_file")
  local original_compose_content
  local compose_content


  if hw_is_wsl; then
    # If WSL is detected and extends_content contains the flag, append "-wsl"
    if [[ "$extends_content" == *"$image_flag+=\"-wsl\""* ]]; then
      hw_flag="$image_flag-wsl"
    fi
  fi

  # Extract the content between the service name and the next service name
  extends_content=$(sed -n "/^  $hw_flag:/,/^[[:space:]]\{2\}[^[:space:]]/ { /^[[:space:]]\{2\}[^[:space:]]/!p }" "$extends_file")
  original_compose_content=$(sed -n "/^  $service_name:/,/^[[:space:]]\{2\}[a-zA-Z0-9_-]\+:/p" "$compose_file" | sed '$d')
  compose_content=$original_compose_content


  # append the image flag to the image field in the compose file
  compose_content=$(echo "$compose_content" | sed "s|\(image:.*:\${IMMICH_VERSION:-release}\)|\1-$image_flag|")

  # Extract only the actual device mappings from extends_content

  declare -a device_groups
  declare -a device_group_settings
  local current_group=""
  local current_settings=""

  # Read each line of extends_content
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]{4}([a-zA-Z_]+): ]]; then
      # If we encounter a new group, store the previous group and its settings
      if [[ -n "$current_group" ]]; then
        device_groups+=("$current_group")
        device_group_settings+=("$current_settings")
      fi
      # Set the new current group
      current_group="${BASH_REMATCH[1]}:" # Get the group name from regex
      current_settings="" # Reset current settings for the new group
    else
      current_settings+="$line"$'\n' # Append to current settings
    fi
  done <<< "$extends_content"

  # Capture the last group settings if any
  if [[ -n "$current_group" ]]; then
    device_groups+=("$current_group")
    device_group_settings+=("$current_settings")
  fi

  # Merge Files
  for i in "${!device_groups[@]}"; do
    local current_device_group=${device_groups[$i]}
    local current_group_settings=$(echo "${device_group_settings[$i]}" | sed "/^$/! s/\$/ /")

    if echo "$compose_content" | grep -q $current_device_group; then  
      local escaped_current_group_settings=$(echo "$current_group_settings" | sed 's/[\/&-]/\\&/g')

      escaped_current_group_settings=$(echo "$escaped_current_group_settings" | sed ':a;N;$!ba;s/\n/\\n/g')

      compose_content=$(echo "$compose_content" | sed "/    $current_device_group/a\\
$escaped_current_group_settings")
    else
      compose_content="${compose_content}
    $current_device_group
$current_group_settings"
    fi

  done

  # Update the compose file with the merged content
  escaped_compose_content=$(echo "$compose_content" | sed ':a;N;$!ba;s/[\/&]/\\&/g; s/\n/\\n/g')

  # Perform the replacement directly, matching the original content based on the service_name
  sed -i "/^  $service_name:/,/^[[:space:]]\{2\}[a-zA-Z0-9_-]\+:/ {
  /^  $service_name:/ {
    s|.*|$escaped_compose_content| 
  }
  /^[[:space:]]*$/!{ # Do not delete empty lines, keep them intact
    /^[[:space:]]\{2\}[a-zA-Z0-9_-]\+:/!d
  }
}" "$compose_file"
  

  # Check the result of the replacement
  if [[ $? -eq 0 ]]; then
    echo "File '$compose_file' updated successfully!"
  else
    echo "Failed to update '$compose_file'."
  fi

}

set_hwa() {
  local image_flag="$1"
  if [[ -n "$image_flag" ]]; then
    return 0
  fi

  if [[ $image_flag == "auto" ]]; then
    if hwa_is_cuda; then
      image_flag="cuda"
    elif hwa_is_armnn; then
      image_flag="armnn"
    elif hwa_is_openvino; then
      image_flag="openvino"
    fi
  fi

  if [[ -n "$image_flag" ]]; then
    local enable_hwa=$(prompt "Would you like to enable hardware acceleration?" "y n" "y")
    if [[ "$enable_hwa" == "y" ]]; then
      local hwa_file="hwaccel.ml.yml"
      if download_file "$hwa_file"; then
        merge_extends "docker-compose.yml" "$hwa_file" "immich-machine-learning" "$image_flag"
        rm -f "$hwa_file"
      else
        echo "  Failed to download $hwa_file. Skipping hardware acceleration."
      fi
    fi
  fi

}

set_hwt() {
  local image_flag="$1"
  if [[ -n "$image_flag" ]]; then
    return 0
  fi

  if [[ $image_flag == "auto" ]]; then
    if hwt_is_nvec; then
      image_flag="nvec"
    elif hwt_is_quicksync; then
      image_flag="quicksync"
    elif hwt_is_rkmpp; then
      image_flag="rkmpp"
    elif hwt_is_vaapi; then
      image_flag="vaapi"
    fi
  fi

  if [[ -n "$image_flag" ]]; then
    local enable_hwt=$(prompt "Would you like to enable hardware transcoding?" "y n" "y")
    if [[ "$enable_hwt" == "y" ]]; then
      local hwt_file="hwaccel.transcoding.yml"
      if download_file "$hwt_file"; then
        merge_extends "docker-compose.yml" "$hwt_file" "immich-machine-learning" "$image_flag"
      else
        echo "  Failed to download $hwt_file. Skipping hardware transcoding."
      fi
    fi
  fi

}

main() {
  local hwt=""
  local hwa=""
  local enable_backups=false
  
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --hwa) hwa="$2"; shift;;
      --hwt) hwt="$2"; shift;;
      --enable-backups) enable_backups=true;;
      *)
        echo "Unknown option: $1"
        return 1
        ;;
    esac
    shift
  done

  echo "Starting Immich installation..."
  local -r RepoUrl='https://github.com/immich-app/immich/releases/latest/download'
  local -a Curl
  if command -v curl >/dev/null; then
    Curl=(curl -fsSL)
  else
    echo 'no curl binary found; please install curl and try again'
    return 14
  fi

  create_immich_directory
  download_file "docker-compose.yml"
  download_file "example.env" ".env"
  generate_random_db_password
  set_hwa "$hwa"
  set_hwt "$hwt"
  if [[ $enable_backups == true ]]; then
    set_backups
  fi
  start_docker_compose
}

main "$@"
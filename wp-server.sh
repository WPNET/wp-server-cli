#!/bin/bash
# WP Server - CLI Tool
VERSION="1.6.17"

# Web root path (relative to user home directory)
WEBROOT_BASE_DIR="files"
WEBROOT_PATH=""

# Function to determine the correct webroot path
function determine_webroot_path() {
  local user_home="$1"
  local default_webroot="${WEBROOT_BASE_DIR}"
  local custom_webroot="${WEBROOT_BASE_DIR}/public"

  if [ -f "$user_home/$default_webroot/wp-load.php" ]; then
    echo "$default_webroot"
  elif [ -f "$user_home/$custom_webroot/wp-load.php" ]; then
    echo "$custom_webroot"
  else
    echo "$default_webroot"
    echo "Warning: wp-load.php not found in '$user_home/$default_webroot' or '$user_home/$custom_webroot'. Defaulting to '$default_webroot'." >&2
  fi
}

# Check if mysql-server package is installed
dpkg -s mysql-server &> /dev/null
if [ $? -eq 0 ]; then
    MYSQL_SERVER_INSTALLED=true
else
    MYSQL_SERVER_INSTALLED=false
fi

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONFIG_FILE="$SCRIPT_DIR/api.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: API config file not found at $CONFIG_FILE"
  exit 1
fi

# Parse API config file
while IFS='=' read -r key value; do
  case "$key" in
    API_KEY)
      API_KEY="$value"
      ;;
    API_URL)
      API_URL="$value"
      ;;
    SERVER_ID)
      SERVER_ID="$value"
      ;;
  esac
done < "$CONFIG_FILE"

# Determine the current user and home path (if running under sudo)
if [ -n "$SUDO_USER" ]; then
  CURRENT_USER="$SUDO_USER"
  USER_HOME_PATH=$(getent passwd "$CURRENT_USER" | cut -d: -f6)
else
  CURRENT_USER=""
  USER_HOME_PATH=""
fi

# Determine WEBROOT_PATH after USER_HOME_PATH is set
if [ -n "$USER_HOME_PATH" ]; then
  WEBROOT_PATH=$(determine_webroot_path "$USER_HOME_PATH")
else
  WEBROOT_PATH="" # Keep WEBROOT_PATH empty if user home path is not determined
fi

# Color codes
RESET='\e[0m'
CYAN='\e[36m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'

# Function to check if SpinupWP plugin is active
function is_spinupwp_plugin_active() {
  if [ -z "$CURRENT_USER" ] || [ -z "$USER_HOME_PATH" ]; then
    return 1
  fi
  # Suppress PHP notices and warnings from wp-cli, and check if the plugin is active
  WP_CLI_PHP_ARGS="-d error_reporting=E_ERROR" sudo -u "$CURRENT_USER" wp plugin is-active spinupwp --path="$USER_HOME_PATH/$WEBROOT_PATH" &> /dev/null
  if [ $? -eq 0 ]; then
    return 0 # Plugin is active
  else
    return 1 # Plugin is not active
  fi
}

SPINUPWP_ACTIVE=false
if is_spinupwp_plugin_active; then
    SPINUPWP_ACTIVE=true
fi

# Function to get PHP version and config path for the current site user
function get_php_fpm_config_for_site_user() {
  local user_home_path="$1"
  
  # Get the actual site user from the home directory ownership
  local site_user=$(stat -c '%U' "$user_home_path" 2>/dev/null)
  
  if [ -z "$site_user" ]; then
    return 1
  fi
  
  # Search for the pool config file in /etc/php/*/fpm/pool.d/{site_user}.conf
  for config in /etc/php/*/fpm/pool.d/"${site_user}".conf; do
    if [ -f "$config" ]; then
      echo "$config"
      return 0
    fi
  done
  
  return 1
}

# Function to update or add PHP FPM config value
function update_php_fpm_value() {
  local php_fpm_conf="$1"
  local key="$2"
  local value="$3"
  
  if [ ! -f "$php_fpm_conf" ]; then
    echo "ERROR: PHP FPM pool config file not found: $php_fpm_conf"
    return 1
  fi

  local pattern="php_admin_value\[${key}\]"
  local line_content="php_admin_value[${key}] = ${value}"
  
  # Check if the setting already exists
  if grep -q "php_admin_value\[${key}\]" "$php_fpm_conf"; then
    # Get current value to check if it needs updating
    local current_value=$(grep "php_admin_value\[${key}\]" "$php_fpm_conf" | head -n1 | sed -e 's/.*= //' | tr -d ' ')
    if [ "$current_value" = "$value" ]; then
      echo "php_admin_value[${key}] is already set to ${value}. Skipping update."
      return 0
    else
      # Update existing value
      if sed -i "s|^php_admin_value\[${key}\] =.*|${line_content}|" "$php_fpm_conf"; then
        echo "Updated php_admin_value[${key}] to ${value} in $php_fpm_conf"
        return 0
      else
        echo "ERROR: Failed to update php_admin_value[${key}] in $php_fpm_conf"
        return 1
      fi
    fi
  else
    # Append new value
    if echo "${line_content}" >> "$php_fpm_conf"; then
      echo "Added php_admin_value[${key}] = ${value} to $php_fpm_conf"
      return 0
    else
      echo "ERROR: Failed to add php_admin_value[${key}] to $php_fpm_conf"
      return 1
    fi
  fi
}

# Function to remove .user.ini file from webroot
function remove_user_ini() {
  if [ -z "$CURRENT_USER" ] || [ -z "$USER_HOME_PATH" ]; then
    echo "Error: Could not determine the user who ran this command. This script must be run with sudo by a non-root user."
    return 1
  fi

  USER_INI_PATH="$USER_HOME_PATH/$WEBROOT_PATH/.user.ini"
  
  if [ -f "$USER_INI_PATH" ]; then
    if rm "$USER_INI_PATH"; then
      echo "Successfully removed .user.ini from $USER_INI_PATH"
      return 0
    else
      echo "ERROR: Failed to remove .user.ini file at $USER_INI_PATH"
      return 1
    fi
  else
    echo ".user.ini file not found at $USER_INI_PATH - nothing to remove."
    return 0
  fi
}

function print_usage() {
  echo ""
  echo -e "${CYAN}WP Server CLI${RESET} - ${YELLOW}v${VERSION}${RESET}"
  echo -e "${CYAN}Usage:${RESET}    wp-server ${GREEN}<command>${RESET}"
  echo ""
  echo -e "${CYAN}Commands:${RESET}"
  echo -e "  ${GREEN}restart <service>${RESET}              Restart a service"
  echo -e "  ${GREEN}timeout [-s <seconds>]${RESET}         Set PHP & Nginx timeouts for the current site. If -s is not provided, the value will be prompted."
  echo -e "  ${GREEN}max-upload [-m <megabytes>]${RESET}    Set PHP & Nginx max upload size for the current site. If -m is not provided, the value will be prompted."
  echo -e "  ${GREEN}max-input-vars [-v <count>]${RESET}    Set PHP max input variables for the current site. If -v is not provided, the value will be prompted."
  echo -e "  ${GREEN}memory-limit [-m <megabytes>]${RESET}  Set PHP memory limit for the current site. If -m is not provided, the value will be prompted."
  echo -e "  ${GREEN}remove-user-ini${RESET}                Remove .user.ini file from the webroot if it exists"
  if $SPINUPWP_ACTIVE; then
    echo -e "  ${GREEN}cache status${RESET}                   Show cache status"
    echo -e "  ${GREEN}cache purge-page${RESET}               Purge Nginx page cache"
    echo -e "  ${GREEN}cache purge-object${RESET}             Purge PHP Object cache (equivalent to wp cache flush)"
  fi
  echo ""
  echo -e "${CYAN}Services for 'restart':${RESET}"
  if $MYSQL_SERVER_INSTALLED; then
    echo -e "  Database:                      ${GREEN}db${RESET} | ${GREEN}mysql${RESET}"
  fi
  echo -e "  PHP:                           ${GREEN}php${RESET} (restarts all runtime versions)"
  echo -e "  PHP Object Cache:              ${GREEN}redis${RESET}"
  echo -e "  Web server:                    ${GREEN}web${RESET} | ${GREEN}nginx${RESET}"
}

function restart_service() {
    local service_to_restart=$1
    local service_name=""

    case "$service_to_restart" in
      nginx|web)
        service_name="nginx"
        ;;
      php)
        service_name="php"
        ;;
      mysql|db)
        service_name="mysql"
        if [[ ! $MYSQL_SERVER_INSTALLED ]]; then
            echo -e "${YELLOW}Warning:${RESET} MySQL server is not installed. Skipping MySQL service restart."
            return 0
        fi
        ;;
      redis)
        service_name="redis"
        ;;
      *)
        echo "Invalid service alias provided to restart_service function: $service_to_restart"
        return 1
        ;;
    esac

    local restart_api_url="$API_URL/servers/$SERVER_ID/services/$service_name/restart"

    RESPONSE=$(curl -s -X POST -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" "$restart_api_url")

    EVENT_ID=$(echo "$RESPONSE" | jq -r '.event_id')
    MESSAGE=$(echo "$RESPONSE" | jq -r '.message')

    if [[ "$EVENT_ID" =~ ^[0-9]+$ ]]; then
      MSG="Service ${YELLOW}${service_name}${RESET} restart initiated. Event ID: ${BLUE}${EVENT_ID}${RESET}"
      # Remove 'Event ID: ...' from the end if present
      MSG_CLEANED=$(echo -e "$MSG" | sed 's/ *Event ID:.*$//')
      echo -e "$MSG_CLEANED"
    elif [ ! -z "$MESSAGE" ]; then
      # Remove 'Event ID: ...' from the end if present in message
      MSG_CLEANED=$(echo "$MESSAGE" | sed 's/ *Event ID:.*$//')
      echo "$MSG_CLEANED"
    else
      echo "Error: Invalid or missing event_id in API response for service $service_name."
      echo "Response: $RESPONSE"
      return 1
    fi
    return 0
}

COMMAND="$1"
ARGUMENT="$2"

if [ -z "$COMMAND" ]; then
  print_usage
  exit 1
fi


case "$COMMAND" in
  -v|--version)
  echo "wp-server version $VERSION"
  exit 0
  ;;
  restart)
  if [ -z "$ARGUMENT" ]; then
    echo "Error: restart command requires a service alias."
    print_usage
    exit 1
  fi
  restart_service "$ARGUMENT"
  ;;
  cache)
  if ! $SPINUPWP_ACTIVE; then
    echo "Error: Not available because the Cache Control plugin is not active."
    exit 1
  fi
  if [ -z "$CURRENT_USER" ] || [ -z "$USER_HOME_PATH" ]; then
    echo "Error: Could not determine the user who ran this command. This script must be run with sudo by a non-root user."
    exit 1
  fi
  case "$ARGUMENT" in
    status)
    WP_CLI_PHP_ARGS="-d error_reporting=E_ERROR" sudo -u "$CURRENT_USER" wp spinupwp status --path="$USER_HOME_PATH/$WEBROOT_PATH"
    echo ""
    echo "NOTE:"
    echo "- To enable / disable the Nginx page cache, please open a support ticket: https://wpnet.nz/ticket/"
    echo "- To enable / disable the Object cache, edit the WP_REDIS_DISABLED constant in wp-config.php."
    ;;
    purge-page)
    WP_CLI_PHP_ARGS="-d error_reporting=E_ERROR" sudo -u "$CURRENT_USER" wp spinupwp cache purge-site --path="$USER_HOME_PATH/$WEBROOT_PATH"
    ;;
    purge-object)
    WP_CLI_PHP_ARGS="-d error_reporting=E_ERROR" sudo -u "$CURRENT_USER" wp cache flush --path="$USER_HOME_PATH/$WEBROOT_PATH"
    ;;
    *)
    echo "Invalid cache command: $ARGUMENT"
    print_usage
    exit 1
    ;;
  esac
  ;;
  timeout)
  SET_TIMEOUT_VALUE=""
  # Parse optional -s or --set flag
  if [ "$ARGUMENT" == "-s" ] || [ "$ARGUMENT" == "--set" ]; then
    SET_TIMEOUT_VALUE="$3"
    if ! [[ "$SET_TIMEOUT_VALUE" =~ ^[0-9]+$ ]]; then
      echo "Error: Invalid timeout value provided with -s/--set. Please provide a number."
      exit 1
    fi
  fi

  if [ -z "$CURRENT_USER" ] || [ -z "$USER_HOME_PATH" ]; then
    echo "Error: Could not determine the user who ran this command. This script must be run with sudo by a non-root user."
    exit 1
  fi

  SITE_NAME=$(basename "$USER_HOME_PATH")
  TIMEOUT_VALUE=""

  if [ -n "$SET_TIMEOUT_VALUE" ]; then
    TIMEOUT_VALUE="$SET_TIMEOUT_VALUE"
    echo "Using provided timeout value: $TIMEOUT_VALUE seconds."
  else
    # If TIMEOUT_VALUE is empty, prompt the user
    read -p "Enter desired PHP and Nginx timeout value in seconds: " USER_INPUT_TIMEOUT
    # Validate input
    if ! [[ "$USER_INPUT_TIMEOUT" =~ ^[0-9]+$ ]]; then
      echo "Error: Invalid input. Please provide a number."
      exit 1
    fi
    TIMEOUT_VALUE="$USER_INPUT_TIMEOUT"
  fi

  # Update PHP FPM pool configuration
  if [ -n "$TIMEOUT_VALUE" ]; then
    # Get PHP FPM config path for this site user
    PHP_FPM_CONF=$(get_php_fpm_config_for_site_user "$USER_HOME_PATH")
    
    if [ -z "$PHP_FPM_CONF" ]; then
      echo "ERROR: Could not find PHP FPM pool config for user at $USER_HOME_PATH"
      exit 1
    fi

    update_php_fpm_value "$PHP_FPM_CONF" "max_execution_time" "${TIMEOUT_VALUE}"
  fi

  # TIMEOUT_VALUE is guaranteed to be set. Proceed with Nginx config.
  NGINX_CONF_PATH="/etc/nginx/sites-available/$SITE_NAME/location/fastcgi-timeout.conf"
  NGINX_CURRENT_TIMEOUT=""

  if [ -f "$NGINX_CONF_PATH" ]; then
    NGINX_CURRENT_TIMEOUT=$(grep "fastcgi_read_timeout" "$NGINX_CONF_PATH" | cut -d' ' -f2 | sed 's/s;//g' | sed 's/[^0-9]*//g')
  fi

  if [ -n "$NGINX_CURRENT_TIMEOUT" ] && [ "$NGINX_CURRENT_TIMEOUT" -eq "$TIMEOUT_VALUE" ]; then
    echo "Nginx fast-cgi timeout is already $TIMEOUT_VALUE seconds. Skipping update."
  else
    mkdir -p "$(dirname "$NGINX_CONF_PATH")" || {
        echo "ERROR: Failed to create directory for nginx config file"
        exit 1
    }
        
    CONF_CONTENT="# Customise fastcgi timeout\nfastcgi_read_timeout ${TIMEOUT_VALUE}s;"
    if echo -e "$CONF_CONTENT" > "$NGINX_CONF_PATH"; then
        echo "Updated Nginx fast-cgi timeout to $TIMEOUT_VALUE seconds."
    else
        echo "ERROR: Failed to write nginx configuration file"
        exit 1
    fi

    # Validate nginx configuration before restarting services
    if nginx -t >/dev/null 2>&1; then
        echo "Nginx configuration is valid."
        echo "Restarting services ..."
        restart_service "php"
        restart_service "nginx"
    else
        echo "ERROR: Nginx configuration is invalid. Services not restarted."
        echo "Please check the nginx configuration at $NGINX_CONF_PATH"
        exit 1
    fi
  fi
  ;;
  max-upload)
  SET_UPLOAD_VALUE=""
  # Parse optional -m or --mb flag
  if [ "$ARGUMENT" == "-m" ] || [ "$ARGUMENT" == "--mb" ]; then
    SET_UPLOAD_VALUE="$3"
    if ! [[ "$SET_UPLOAD_VALUE" =~ ^[0-9]+$ ]]; then
      echo "Error: Invalid upload size value provided with -m/--mb. Please provide a number."
      exit 1
    fi
  fi

  if [ -z "$CURRENT_USER" ] || [ -z "$USER_HOME_PATH" ]; then
    echo "Error: Could not determine the user who ran this command. This script must be run with sudo by a non-root user."
    exit 1
  fi

  SITE_NAME=$(basename "$USER_HOME_PATH")
  UPLOAD_VALUE=""

  if [ -n "$SET_UPLOAD_VALUE" ]; then
    # Explicit size provided - use it for both upload_max_filesize and calculate post_max_size
    UPLOAD_VALUE="$SET_UPLOAD_VALUE"
    echo "Using provided upload size: $UPLOAD_VALUE MB."
  else
    # If UPLOAD_VALUE is still empty, prompt the user
    read -p "Enter desired max upload size in megabytes: " USER_INPUT_UPLOAD
    # Validate input
    if ! [[ "$USER_INPUT_UPLOAD" =~ ^[0-9]+$ ]]; then
      echo "Error: Invalid input. Please provide a number."
      exit 1
    fi
    UPLOAD_VALUE="$USER_INPUT_UPLOAD"
  fi

  # Calculate desired post_max_size (upload + 2)
  DESIRED_POST_MAX=$((UPLOAD_VALUE + 2))

  # Update PHP FPM pool configuration
  if [ -n "$UPLOAD_VALUE" ]; then
    # Get PHP FPM config path for this site user
    PHP_FPM_CONF=$(get_php_fpm_config_for_site_user "$USER_HOME_PATH")
    
    if [ -z "$PHP_FPM_CONF" ]; then
      echo "ERROR: Could not find PHP FPM pool config for user at $USER_HOME_PATH"
      exit 1
    fi

    update_php_fpm_value "$PHP_FPM_CONF" "upload_max_filesize" "${UPLOAD_VALUE}M"
    update_php_fpm_value "$PHP_FPM_CONF" "post_max_size" "${DESIRED_POST_MAX}M"
  fi

  # UPLOAD_VALUE is guaranteed to be set. Proceed with Nginx config.
  NGINX_CONF_PATH="/etc/nginx/sites-available/$SITE_NAME/server/client-max-body-size.conf"
  NGINX_CURRENT_UPLOAD=""

  if [ -f "$NGINX_CONF_PATH" ]; then
    NGINX_CURRENT_UPLOAD=$(grep "client_max_body_size" "$NGINX_CONF_PATH" | cut -d' ' -f2 | sed 's/m;//g' | sed 's/[^0-9]*//g')
    # Validate that NGINX_CURRENT_UPLOAD is a valid number
    if [ -n "$NGINX_CURRENT_UPLOAD" ] && ! [[ "$NGINX_CURRENT_UPLOAD" =~ ^[0-9]+$ ]]; then
      NGINX_CURRENT_UPLOAD=""
    fi
  fi

  if [ -n "$NGINX_CURRENT_UPLOAD" ] && [ "$NGINX_CURRENT_UPLOAD" -eq "$UPLOAD_VALUE" ]; then
    echo "Nginx client_max_body_size is already $UPLOAD_VALUE MB. Skipping update."
  else
    mkdir -p "$(dirname "$NGINX_CONF_PATH")" || {
        echo "ERROR: Failed to create directory for nginx config file"
        exit 1
    }
        
    CONF_CONTENT="# Customise client max body size\nclient_max_body_size ${UPLOAD_VALUE}m;"
    if echo -e "$CONF_CONTENT" > "$NGINX_CONF_PATH"; then
        echo "Updated Nginx client_max_body_size to $UPLOAD_VALUE MB."
    else
        echo "ERROR: Failed to write nginx configuration file"
        exit 1
    fi

    # Validate nginx configuration before restarting services
    if nginx -t >/dev/null 2>&1; then
        echo "Nginx configuration is valid."
        echo "Restarting services ..."
        restart_service "php"
        restart_service "nginx"
    else
        echo "ERROR: Nginx configuration is invalid. Services not restarted."
        echo "Please check the nginx configuration at $NGINX_CONF_PATH"
        exit 1
    fi
  fi
  ;;
  max-input-vars)
  SET_INPUT_VARS_VALUE=""
  # Parse optional -v flag
  if [ "$ARGUMENT" == "-v" ]; then
    SET_INPUT_VARS_VALUE="$3"
    if ! [[ "$SET_INPUT_VARS_VALUE" =~ ^[0-9]+$ ]]; then
      echo "Error: Invalid input vars value provided with -v. Please provide a number."
      exit 1
    fi
  fi

  if [ -z "$CURRENT_USER" ] || [ -z "$USER_HOME_PATH" ]; then
    echo "Error: Could not determine the user who ran this command. This script must be run with sudo by a non-root user."
    exit 1
  fi

  INPUT_VARS_VALUE=""

  if [ -n "$SET_INPUT_VARS_VALUE" ]; then
    INPUT_VARS_VALUE="$SET_INPUT_VARS_VALUE"
    echo "Using provided max input vars value: $INPUT_VARS_VALUE"
  else
    # If INPUT_VARS_VALUE is empty, prompt the user
    read -p "Enter desired max input variables value: " USER_INPUT_VARS
    # Validate input
    if ! [[ "$USER_INPUT_VARS" =~ ^[0-9]+$ ]]; then
      echo "Error: Invalid input. Please provide a number."
      exit 1
    fi
    INPUT_VARS_VALUE="$USER_INPUT_VARS"
  fi

  # Update PHP FPM pool configuration
  if [ -n "$INPUT_VARS_VALUE" ]; then
    # Get PHP FPM config path for this site user
    PHP_FPM_CONF=$(get_php_fpm_config_for_site_user "$USER_HOME_PATH")
    
    if [ -z "$PHP_FPM_CONF" ]; then
      echo "ERROR: Could not find PHP FPM pool config for user at $USER_HOME_PATH"
      exit 1
    fi

    if update_php_fpm_value "$PHP_FPM_CONF" "max_input_vars" "${INPUT_VARS_VALUE}"; then
      # Restart PHP service
      echo "Restarting PHP service ..."
      restart_service "php"
    else
      exit 1
    fi
  fi
  ;;
  memory-limit)
  SET_MEMORY_VALUE=""
  # Parse optional -m flag
  if [ "$ARGUMENT" == "-m" ]; then
    SET_MEMORY_VALUE="$3"
    if ! [[ "$SET_MEMORY_VALUE" =~ ^[0-9]+$ ]]; then
      echo "Error: Invalid memory limit value provided with -m. Please provide a number."
      exit 1
    fi
  fi

  if [ -z "$CURRENT_USER" ] || [ -z "$USER_HOME_PATH" ]; then
    echo "Error: Could not determine the user who ran this command. This script must be run with sudo by a non-root user."
    exit 1
  fi

  MEMORY_VALUE=""

  if [ -n "$SET_MEMORY_VALUE" ]; then
    MEMORY_VALUE="$SET_MEMORY_VALUE"
    echo "Using provided memory limit value: $MEMORY_VALUE MB"
  else
    # If MEMORY_VALUE is empty, prompt the user
    read -p "Enter desired PHP memory limit in megabytes: " USER_INPUT_MEMORY
    # Validate input
    if ! [[ "$USER_INPUT_MEMORY" =~ ^[0-9]+$ ]]; then
      echo "Error: Invalid input. Please provide a number."
      exit 1
    fi
    MEMORY_VALUE="$USER_INPUT_MEMORY"
  fi

  # Update PHP FPM pool configuration
  if [ -n "$MEMORY_VALUE" ]; then
    # Get PHP FPM config path for this site user
    PHP_FPM_CONF=$(get_php_fpm_config_for_site_user "$USER_HOME_PATH")
    
    if [ -z "$PHP_FPM_CONF" ]; then
      echo "ERROR: Could not find PHP FPM pool config for user at $USER_HOME_PATH"
      exit 1
    fi

    if update_php_fpm_value "$PHP_FPM_CONF" "memory_limit" "${MEMORY_VALUE}M"; then
      # Restart PHP service
      echo "Restarting PHP service ..."
      restart_service "php"
    else
      exit 1
    fi
  fi
  ;;
  remove-user-ini)
  remove_user_ini
  ;;
  *)
  echo "Invalid command: $COMMAND"
  print_usage
  exit 1
  ;;
esac

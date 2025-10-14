#!/bin/bash
# WP Server - CLI Tool
VERSION="1.5.1"

# Web root path (relative to user home directory)
WEBROOT_PATH="files"

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

# Color codes
RESET='\e[0m'
CYAN='\e[36m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'

# Function to check if cache management plugin is active
function is_cache_plugin_active() {
  if [ -z "$CURRENT_USER" ] || [ -z "$USER_HOME_PATH" ]; then
    return 1
  fi
  # Suppress PHP notices and warnings from wp-cli, and check if the plugin is active
  WP_CLI_PHP_ARGS="-d error_reporting=E_ERROR" sudo -u "$CURRENT_USER" wp plugin is-active wp-server-cache --path="$USER_HOME_PATH/$WEBROOT_PATH" &> /dev/null
  if [ $? -eq 0 ]; then
    return 0 # Plugin is active
  else
    return 1 # Plugin is not active
  fi
}

CACHE_PLUGIN_ACTIVE=false
if is_cache_plugin_active; then
    CACHE_PLUGIN_ACTIVE=true
fi

function print_usage() {
  echo -e "${CYAN}Usage:${RESET}    wp-server ${GREEN}<command>${RESET}"
  echo ""
  echo -e "${CYAN}Commands:${RESET}"
  echo -e "  ${GREEN}restart <service>${RESET}      Restart a service"
  echo -e "  ${GREEN}timeout [-s <seconds>]${RESET} Set PHP and Nginx timeouts for the current site. If -s is not provided, the value will be read from .user.ini or prompted."
  if $CACHE_PLUGIN_ACTIVE; then
    echo -e "  ${GREEN}cache status${RESET}           Show cache status"
    echo -e "  ${GREEN}cache purge-page${RESET}       Purge Nginx page cache"
    echo -e "  ${GREEN}cache purge-object${RESET}     Purge PHP Object cache (equivalent to wp cache flush)"
  fi
  echo ""
  echo -e "${CYAN}Services for 'restart':${RESET}"
  echo -e "  Cache:        ${GREEN}redis${RESET}"
  if $MYSQL_SERVER_INSTALLED; then
    echo -e "  Database:     ${GREEN}db${RESET} | ${GREEN}mysql${RESET}"
  fi
  echo -e "  PHP:          ${GREEN}php${RESET} (restarts all runtime versions)"
  echo -e "  Web server:   ${GREEN}web${RESET} | ${GREEN}nginx${RESET}"
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
  if ! $CACHE_PLUGIN_ACTIVE; then
    echo "Error: Cache commands are not available because the cache management plugin is not active."
    exit 1
  fi
  if [ -z "$CURRENT_USER" ] || [ -z "$USER_HOME_PATH" ]; then
    echo "Error: Could not determine the user who ran this command. This script must be run with sudo by a non-root user."
    exit 1
  fi
  case "$ARGUMENT" in
    status)
    WP_CLI_PHP_ARGS="-d error_reporting=E_ERROR" sudo -u "$CURRENT_USER" wp wp-server-cache status --path="$USER_HOME_PATH/$WEBROOT_PATH"
    echo ""
    echo "NOTE:"
    echo "- To enable / disable the Object cache, edit the WP_REDIS_DISABLED constant in wp-config.php."
    echo "- To enable / disable the Nginx page cache, please open a support ticket: https://wpnet.nz/ticket/"
    ;;
    purge-page)
    WP_CLI_PHP_ARGS="-d error_reporting=E_ERROR" sudo -u "$CURRENT_USER" wp wp-server-cache purge-site --path="$USER_HOME_PATH/$WEBROOT_PATH"
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

  # TODO: Fix path to avoid hardcoding /files. need to get the site path dynamically from the API?
  USER_INI_PATH="$USER_HOME_PATH/$WEBROOT_PATH/.user.ini"
  TIMEOUT_VALUE=""

  if [ -n "$SET_TIMEOUT_VALUE" ]; then
    TIMEOUT_VALUE="$SET_TIMEOUT_VALUE"
    echo "Using provided timeout value: $TIMEOUT_VALUE seconds."
  else
    # Try to read existing timeout value
    if [ -f "$USER_INI_PATH" ]; then
      TIMEOUT_VALUE=$(grep "max_execution_time" "$USER_INI_PATH" | cut -d'=' -f2 | tr -d ' ' | sed 's/[^0-9]*//g')
      if [ -n "$TIMEOUT_VALUE" ]; then
        echo "Found existing PHP timeout of $TIMEOUT_VALUE seconds in .user.ini"
      else
        echo "No valid 'max_execution_time' found in existing .user.ini."
      fi
    fi

    # If TIMEOUT_VALUE is still empty, prompt the user
    if [ -z "$TIMEOUT_VALUE" ]; then
      read -p "Enter desired PHP and Nginx timeout value in seconds: " USER_INPUT_TIMEOUT
      # Validate input
      if ! [[ "$USER_INPUT_TIMEOUT" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid input. Please provide a number."
        exit 1
      fi
      TIMEOUT_VALUE="$USER_INPUT_TIMEOUT"
    fi
  fi

  # Create/update .user.ini if TIMEOUT_VALUE was set or changed
  if [ -n "$TIMEOUT_VALUE" ]; then
    mkdir -p "$(dirname "$USER_INI_PATH")" || {
        echo "ERROR: Failed to create directory for .user.ini file"
        exit 1
    }
    CURRENT_INI_TIMEOUT=""
    if [ -f "$USER_INI_PATH" ]; then
      CURRENT_INI_TIMEOUT=$(grep "max_execution_time" "$USER_INI_PATH" | cut -d'=' -f2 | tr -d ' ' | sed 's/[^0-9]*//g')
    fi

    if [ -n "$CURRENT_INI_TIMEOUT" ] && [ "$CURRENT_INI_TIMEOUT" -eq "$TIMEOUT_VALUE" ]; then
      echo "PHP max_execution_time is already $TIMEOUT_VALUE seconds. Skipping update."
    elif grep -q "max_execution_time" "$USER_INI_PATH"; then
      if sed -i "s/^max_execution_time =.*/max_execution_time = $TIMEOUT_VALUE/" "$USER_INI_PATH"; then
        echo "Updated max_execution_time in .user.ini to $TIMEOUT_VALUE seconds."
      else
        echo "ERROR: Failed to update .user.ini file"
        exit 1
      fi
    else
      if echo "max_execution_time = $TIMEOUT_VALUE" >> "$USER_INI_PATH"; then
        echo "Added max_execution_time to .user.ini with value $TIMEOUT_VALUE seconds."
      else
        echo "ERROR: Failed to write to .user.ini file"
        exit 1
      fi
    fi
    if ! chown "$CURRENT_USER":"$CURRENT_USER" "$USER_INI_PATH"; then
      echo "ERROR: Failed to set ownership on .user.ini file"
      exit 1
    fi
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
  *)
  echo "Invalid command: $COMMAND"
  print_usage
  exit 1
  ;;
esac

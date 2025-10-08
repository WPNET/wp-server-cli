#!/bin/bash
# WP Server - Service Management
VERSION="1.4.9"

# Check if mysql-server package is installed
dpkg -s mysql-server &> /dev/null
if [ $? -eq 0 ]; then
    MYSQL_SERVER_INSTALLED=true
else
    MYSQL_SERVER_INSTALLED=false
fi


CONFIG_FILE="/opt/wp-server/api.conf"

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

function print_usage() {
  echo -e "${CYAN}Usage:${RESET}    wp-server ${GREEN}<command>${RESET}"
  echo ""
  echo -e "${CYAN}Commands:${RESET}"
  echo -e "  ${GREEN}restart <service>${RESET}      Restart a service"
  echo -e "  ${GREEN}timeout [-s <seconds>]${RESET} Set PHP and Nginx timeouts for the current site. If -s is not provided, the value will be read from .user.ini or prompted."
  echo -e "  ${GREEN}cache status${RESET}           Show cache status"
  echo -e "  ${GREEN}cache purge-page${RESET}       Purge Nginx page cache"
  echo -e "  ${GREEN}cache purge-object${RESET}     Purge object cache (equivalent to wp cache flush)"
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
      echo -e "Service ${YELLOW}${service_name}${RESET} restart initiated. Event ID: ${BLUE}${EVENT_ID}${RESET}"
    elif [ ! -z "$MESSAGE" ]; then
      echo "$MESSAGE"
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
  if [ -z "$CURRENT_USER" ] || [ -z "$USER_HOME_PATH" ]; then
    echo "Error: Could not determine the user who ran this command. This script must be run with sudo by a non-root user."
    exit 1
  fi
  case "$ARGUMENT" in
    status)
    sudo -u "$CURRENT_USER" wp spinupwp status --path="$USER_HOME_PATH/files"
    ;;
    purge-page)
    sudo -u "$CURRENT_USER" wp spinupwp cache purge-site --path="$USER_HOME_PATH/files"
    ;;
    purge-object)
    sudo -u "$CURRENT_USER" wp cache flush --path="$USER_HOME_PATH/files"
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

  # TODO: Fix path to avoid hardcoding /files. need to get the site path dynamically from spinupwp api?
  USER_INI_PATH="$USER_HOME_PATH/files/.user.ini"
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
    mkdir -p "$(dirname "$USER_INI_PATH")"
    CURRENT_INI_TIMEOUT=""
    if [ -f "$USER_INI_PATH" ]; then
      CURRENT_INI_TIMEOUT=$(grep "max_execution_time" "$USER_INI_PATH" | cut -d'=' -f2 | tr -d ' ' | sed 's/[^0-9]*//g')
    fi

    if [ -n "$CURRENT_INI_TIMEOUT" ] && [ "$CURRENT_INI_TIMEOUT" -eq "$TIMEOUT_VALUE" ]; then
      echo "PHP max_execution_time is already $TIMEOUT_VALUE seconds. Skipping update."
    elif grep -q "max_execution_time" "$USER_INI_PATH"; then
      sed -i "s/^max_execution_time =.*/max_execution_time = $TIMEOUT_VALUE/" "$USER_INI_PATH"
      echo "Updated max_execution_time in .user.ini to $TIMEOUT_VALUE seconds."
    else
      echo "max_execution_time = $TIMEOUT_VALUE" >> "$USER_INI_PATH"
      echo "Added max_execution_time to .user.ini with value $TIMEOUT_VALUE seconds."
    fi
    chown "$CURRENT_USER":"$CURRENT_USER" "$USER_INI_PATH"
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
    mkdir -p "$(dirname "$NGINX_CONF_PATH")"
        
    CONF_CONTENT="# Customise fastcgi timeout\nfastcgi_read_timeout ${TIMEOUT_VALUE}s;"
    echo -e "$CONF_CONTENT" > "$NGINX_CONF_PATH"
    echo "Updated Nginx fast-cgi timeout to $TIMEOUT_VALUE seconds."

    echo "Restarting services ..."
    restart_service "php"
    restart_service "nginx"
  fi
  ;;
  *)
  echo "Invalid command: $COMMAND"
  print_usage
  exit 1
  ;;
esac

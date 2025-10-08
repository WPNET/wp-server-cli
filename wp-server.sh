#!/bin/bash
# WP Server - Service Management
VERSION="1.3.1"

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
  echo -e "  ${GREEN}restart <service>${RESET}   Restart a service"
  echo -e "  ${GREEN}timeout${RESET}             Set PHP and Nginx timeouts for the current site"
  echo ""
  echo -e "${CYAN}Services for 'restart':${RESET}"
  echo -e "  PHP:          ${GREEN}php${RESET} (restarts all runtime versions)"
  echo -e "  Web server:   ${GREEN}web${RESET} | ${GREEN}nginx${RESET}"
  if $MYSQL_SERVER_INSTALLED; then
    echo -e "  Database:     ${GREEN}db${RESET} | ${GREEN}mysql${RESET}"
  fi
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
        ;;
      *)
        echo "Invalid service alias provided to restart_service function: $service_to_restart"
        return 1
        ;;
    esac

    if [[ ! $MYSQL_SERVER_INSTALLED ]] && [[ $service_name == "mysql" ]]; then
      echo -e "${YELLOW}Warning:${RESET} MySQL server is not installed. Skipping MySQL service restart."
      return 0
    fi

    local restart_api_url="$API_URL/$SERVER_ID/services/$service_name/restart"

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
  timeout)
    CURRENT_USER="$SUDO_USER"
    if [ -z "$CURRENT_USER" ]; then
        echo "Error: Could not determine the user who ran this command. This script must be run with sudo by a non-root user."
        exit 1
    fi

    USER_HOME_PATH=$(getent passwd "$CURRENT_USER" | cut -d: -f6)
    SITE_NAME=$(basename "$USER_HOME_PATH")

    USER_INI_PATH="/sites/$SITE_NAME/files/.user.ini"
    TIMEOUT_VALUE=""

    if [ -f "$USER_INI_PATH" ]; then
        TIMEOUT_VALUE=$(grep "max_execution_time" "$USER_INI_PATH" | cut -d'=' -f2 | tr -d ' ' | sed 's/[^0-9]*//g')
        echo "Found existing timeout of $TIMEOUT_VALUE seconds in $USER_INI_PATH"
    else
        read -p "Enter timeout value in seconds: " TIMEOUT_VALUE
        # Validate input
        if ! [[ "$TIMEOUT_VALUE" =~ ^[0-9]+$ ]]; then
            echo "Error: Invalid input. Please provide a number."
            exit 1
        fi
        mkdir -p "$(dirname "$USER_INI_PATH")"
        echo "max_execution_time = $TIMEOUT_VALUE" > "$USER_INI_PATH"
        chown "$CURRENT_USER":"$CURRENT_USER" "$USER_INI_PATH"
        echo "Created $USER_INI_PATH with timeout of $TIMEOUT_VALUE seconds."
    fi

    NGINX_CONF_PATH="/etc/nginx/sites-available/$SITE_NAME/location/fastcgi-timeout.conf"
    mkdir -p "$(dirname "$NGINX_CONF_PATH")"
    
    CONF_CONTENT="# Customise fastcgi timeout\nfastcgi_read_timeout ${TIMEOUT_VALUE}s;"
    echo -e "$CONF_CONTENT" > "$NGINX_CONF_PATH"
    echo "Updated Nginx timeout in $NGINX_CONF_PATH"

    echo "Restarting services to apply changes..."
    restart_service "php"
    restart_service "nginx"
    ;;
  *)
    echo "Invalid command: $COMMAND"
    print_usage
    exit 1
    ;;
esac

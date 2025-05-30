#!/bin/bash
# WP Server - Service Restart
# Version: 1.1.1

# Check if mysql-server package is installed
dpkg -s mysql-server &> /dev/null
if [ $? -eq 0 ]; then
    MYSQL_SERVER_INSTALLED=true
else
    MYSQL_SERVER_INSTALLED=false
fi

SERVICE_ALIAS="$1"
CONFIG_FILE="/opt/wp-restart/api.conf"

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

if [ -z "$SERVICE_ALIAS" ]; then
  echo -e "${CYAN}Usage:${RESET}    wp-restart ${GREEN}<service>${RESET}"
  echo -e "${CYAN}Services:${RESET} PHP:          ${GREEN}php${RESET} (restarts all runtime versions)"
  echo -e "          Web server:   ${GREEN}web${RESET} | ${GREEN}nginx${RESET}"
  if $MYSQL_SERVER_INSTALLED; then
    echo -e "          Database:     ${GREEN}db${RESET} | ${GREEN}mysql${RESET}"
  fi  
  exit 1
fi

case "$SERVICE_ALIAS" in
  nginx|web)
    SERVICE_NAME="nginx"
    ;;
  php)
    SERVICE_NAME="php"
    ;;
  mysql|db)
    SERVICE_NAME="mysql"
    ;;
  *)
    echo "Invalid service alias. Run script without arguments to see available services."
    exit 1
    ;;
esac

if [[ ! $MYSQL_SERVER_INSTALLED ]] && [[ $SERVICE_NAME == "mysql" || $SERVICE_NAME == "db" ]]; then
  echo -e "${YELLOW}Warning:${RESET} MySQL server is not installed. Skipping MySQL service restart."
  exit 0
fi

API_URL="$API_URL/$SERVER_ID/services/$SERVICE_NAME/restart"

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  "$API_URL")

EVENT_ID=$(echo "$RESPONSE" | jq -r '.event_id')
MESSAGE=$(echo "$RESPONSE" | jq -r '.message')

if [[ "$EVENT_ID" =~ ^[0-9]+$ ]]; then
  echo -e "Service ${YELLOW}${SERVICE_NAME}${RESET} restart initiated. Event ID: ${BLUE}${EVENT_ID}${RESET}"
elif [ ! -z "$MESSAGE" ]; then
  echo "$MESSAGE"
else
  echo "Error: Invalid or missing event_id in API response."
  echo "Response: $RESPONSE"
  exit 1
fi

#!/bin/bash
# WP Server - Service Restart
# Version: 1.0.0

SERVICE_ALIAS="$1"
CONFIG_FILE="/opt/wp-restart/api.conf"

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
  echo -e "          Database:     ${GREEN}db${RESET} | ${GREEN}mysql${RESET}"
  echo -e "          Web server:   ${GREEN}web${RESET} | ${GREEN}nginx${RESET}"
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
    echo "Invalid service alias. Must be one of: nginx, web, php, mysql, db"
    exit 1
    ;;
esac

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

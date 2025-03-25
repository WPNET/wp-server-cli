#!/bin/bash
# WP Server - Service Restart - Setup
# This script will configure the sudoers file and create a wrapper script for a user to run the 'wp-restart' command.
# Version: 1.1.1

# script name
SCRIPT_NAME="wp-restart"
# install directories
INSTALL_DIR="/opt/$SCRIPT_NAME"
LOCAL_INSTALL_DIR=".local/bin"
# Configuration file
CONFIG_FILE="$INSTALL_DIR/api.conf"
# Get hostname
HOSTNAME=$(hostname -f)
# Get script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# confirmation helper
function get_confirmation() {
    while true; do
        read -p "$(echo -e "\\nCONFIRM: ${1} Are you sure? [Yes/no]") " user_input
        case $user_input in
            [Yy]* ) break;;
            "" ) break;;
            [Nnc]* ) return 1;;
            * ) echo "Please respond yes [Y/y/{enter}] or no [n/c].";;
        esac
    done
    return 0
}

#######################################################
#### Check api.conf
#######################################################

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Configuration file not found: $CONFIG_FILE"

  # Prompt user to create config file
  if ( get_confirmation "Create a new configuration file?" ); then
    echo "Creating new configuration file: $CONFIG_FILE"
    # prompt for API_KEY
    read -p "Enter API key: " API_KEY
    # prompt for API_URL  (e.g. https://api.wpnet.nz/v1/servers)
    read -p "Enter API URL: " API_URL
    # Write to config file
    echo "API_KEY=$API_KEY" > "$CONFIG_FILE"
    echo "API_URL=$API_URL" >> "$CONFIG_FILE"
    echo "'$CONFIG_FILE' file created."
  else
    echo "Cancelled"
    exit 1
  fi
else
  echo "Configuration file found: $CONFIG_FILE"
  # Prompt user to edit config file
  if ( get_confirmation "Edit configuration file?" ); then
    nano "$CONFIG_FILE"
  fi
fi

# Set API key & URL
while IFS='=' read -r key value; do
  case "$key" in
    API_KEY)
      API_KEY="$value"
      ;;
    API_URL)
      API_URL="$value"
      ;;
  esac
done < "$CONFIG_FILE"

if [[ -z "$API_KEY" || -z "$API_URL" ]]; then
  echo "ERROR: Configuration file is missing API_KEY or API_URL"
  exit 1
fi

# Set permissions
chmod 0600 "$CONFIG_FILE"
chmod 0700 "$SCRIPT_DIR"/restart.sh

# Get ALL servers from API
SERVERS_JSON=$(curl -s -X GET \
  "$API_URL/?limit=100" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer $API_KEY")

#######################################################
#### SET SERVER_ID
#######################################################

# Find server ID based on hostname
SERVER_ID=$(echo "$SERVERS_JSON" | jq -r ".data[] | select(.name == \"$HOSTNAME\") | .id")
echo "Server $HOSTNAME is server ID: $SERVER_ID"

# Find and replace SERVER_ID in config file
if grep -q "^SERVER_ID=" "$CONFIG_FILE"; then
  sed -i "s/^SERVER_ID=.*/SERVER_ID=$SERVER_ID/" "$CONFIG_FILE"
else
  echo "SERVER_ID=$SERVER_ID" >> "$CONFIG_FILE"
fi
echo "Server ID $SERVER_ID written to $CONFIG_FILE"

#######################################################
#### Get SELECTED_USER and HOME_PATH
#######################################################

# Get all users
USER_LIST=$(getent passwd)
# Filter users matching "::/sites/"
SITES_USERS=$(echo "$USER_LIST" | grep "::/sites/")

# Extract usernames and display numbered list
echo "Available users with /sites directories:"
echo "$SITES_USERS" | awk -F":" '{print NR ": " $1}'

while true; do
  # Prompt user for selection
  read -p "Select a USER (c or x to cancel): " USER_NUM

  case "$USER_NUM" in
    c|x)
      echo "Cancelled."
      exit 1
      ;;
    [0-9]*)
      # Extract selected username
      SELECTED_USER=$(echo "$SITES_USERS" | awk -F":" "NR==$USER_NUM {print \$1}")
      # Check if a valid number was entered
      if [ -z "$SELECTED_USER" ]; then
        echo "Invalid user. Please try again."
      else
        break
      fi
      ;;
    *)
      echo "Invalid input. Please enter a number, c, or x."
      ;;
  esac
done

# Set user's home directory
USER_HOME_PATH=$(getent passwd "$SELECTED_USER" | cut -d: -f6)
echo "Selected user: '${SELECTED_USER}' home directory is: ${USER_HOME_PATH}"

#######################################################
#### Define the SUDOERS file
#######################################################

echo "Configuring sudoers file for user '${SELECTED_USER}'"
SUDOERS_PATH="/etc/sudoers.d"
SUDOERS_FILE="$SCRIPT_NAME-${SELECTED_USER}"
SUDOERS_FILE="$SUDOERS_PATH/$SUDOERS_FILE"

# only run if same sudoers config doesn't exist
if [ ! -f "$SUDOERS_FILE" ]; then
    # Check if existing sudoers config is OK, before we mess with it
    echo "Checking sudo syntax with visudo ..."
    if visudo -c; then
        echo "Current sudoers syntax is correct."
    elif ( get_confirmation "CHMOD all files in $SUDOERS_PATH to 0440?" ); then
        chmod 0440 $SUDOERS_PATH/*
    fi
    # Define the sudo rules
    SUDO_RULES="${SELECTED_USER} ALL=(root) NOPASSWD: $INSTALL_DIR/restart.sh"

    echo "Creating sudoers file at $SUDOERS_FILE"
    echo -e "$SUDO_RULES" > "$SUDOERS_FILE"
    chmod 0440 "$SUDOERS_FILE" # important!

    # Verify the syntax using visudo -c -f
    if visudo -c -f "$SUDOERS_FILE" > /dev/null 2>&1; then
        echo "Sudoers syntax is correct."
    else
        echo "ERROR: Sudoers syntax check failed. Rolling back ..."
        rm -v "$SUDOERS_FILE"
        echo -e "\nSudoers configuration failed!"
        exit 1 # error
    fi
    echo -e "\nSudoers configuration complete."
else
    echo -e "\nSudoers file already exists."
    if ( get_confirmation "Display existing sudoers file?" ); then
        cat "$SUDOERS_FILE"
    fi
    if ( ! get_confirmation "Keep existing sudoers file?" ); then
        rm -v "$SUDOERS_FILE"
        echo "Checking sudo syntax with visudo ..."
        # if visudo -c > /dev/null 2>&1; then
        if visudo -c; then
            echo "Sudoers syntax is correct."
        else
            echo "ERROR: Sudoers syntax check failed! There may be a problem, check $SUDOERS_PATH/"
        fi
        echo -e "\nExiting ... you will need to re-run this script to create a new sudoers file."
        exit
    else
        echo "Continuing with existing sudoers config ..."
    fi
fi

#######################################################
#### Create wrapper script
#######################################################

WRAPPER_SCRIPT="$USER_HOME_PATH/$LOCAL_INSTALL_DIR/$SCRIPT_NAME"
printf '#!/bin/bash\n# WP Server - Service Restart wrapper\n# This script will not work without appropriate permissions configured with sudo.\n# Contact WP NET support for help.\nsudo %s/restart.sh "$@"' "$INSTALL_DIR" > "$WRAPPER_SCRIPT"
sudo chown "$SELECTED_USER":"$SELECTED_USER" "$WRAPPER_SCRIPT"
chmod 0700 "$WRAPPER_SCRIPT"

echo "The user '${SELECTED_USER}' can now login and run: $SCRIPT_NAME <service>"
exit

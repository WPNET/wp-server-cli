# GitHub Copilot Instructions

This document provides instructions for GitHub Copilot to effectively assist in the development of the `wp-restart` project.

## Project Overview

`wp-restart` is a set of shell scripts that allows a designated non-root user on a server to restart services (PHP, Nginx, MySQL) by making a call to a remote API.

The project consists of two main scripts:
- `setup.sh`: An interactive setup script that configures the environment. It prompts for API credentials, identifies the server, and configures `sudo` to allow a specific user to run the `restart.sh` script with root privileges.
- `restart.sh`: The core script that handles the service restart requests. It reads the service to be restarted from the command line arguments and sends a POST request to the configured API endpoint.

A configuration file, `api.conf`, is created by `setup.sh` in `/opt/wp-restart/` to store the `API_KEY`, `API_URL`, and `SERVER_ID`.

## Key Workflows

### Setup

The setup process is initiated by running `bash setup.sh`. This script performs the following actions:
1.  **Configuration:** It creates and populates `api.conf` with the necessary API credentials.
2.  **Server Identification:** It fetches a list of servers from the API and matches the server's hostname to find the correct `SERVER_ID`.
3.  **User Selection:** It lists users with home directories in `/sites/` and prompts for which user should be granted restart permissions.
4.  **Sudoers Configuration:** It creates a file in `/etc/sudoers.d/` to grant the selected user passwordless `sudo` access to the `restart.sh` script.
5.  **Wrapper Script:** It creates a wrapper script in the user's `~/.local/bin` directory, which allows the user to run `wp-restart` without needing to know the full path to the script.

### Restarting a Service

Once set up, the designated user can restart a service by running:
`wp-restart <service_alias>`

The supported aliases are:
-   `php`: Restarts all PHP versions.
-   `web` or `nginx`: Restarts the Nginx web server.
-   `db` or `mysql`: Restarts the MySQL database server.

The `restart.sh` script is executed with `sudo` via the wrapper script. It constructs the API URL and sends a POST request with the API key for authorization.

## Development Conventions

-   **Shell:** The scripts are written in Bash.
-   **Dependencies:** The scripts rely on `curl` for making API requests and `jq` for parsing JSON responses. `setup.sh` also uses `visudo` to validate the sudoers file syntax.
-   **Configuration:** All configuration is stored in `/opt/wp-restart/api.conf`.
-   **Installation:** The scripts are intended to be cloned into `/opt/wp-restart`.

When making changes, ensure that both `setup.sh` and `restart.sh` are updated if the core logic or configuration changes. Pay close attention to file paths and permissions, as they are critical for the correct functioning of the tool.

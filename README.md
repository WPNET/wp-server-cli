# wp-server
`wp-server` is a command-line tool for managing common server and site-specific operations. It provides "site" users with simple CLI tools for tasks such as restarting services, managing cache, adjusting PHP timeouts, and configuring upload limits.

## Installation

1.  **Clone the repository:**
    ```bash
    # Login as root or a sudo user
    cd /opt
    git clone git@github.com:wpnet/wp-server.git
    cd wp-server
    ```

2.  **Run the setup script:**
    The setup script will guide you through creating the `api.conf` file, which stores the necessary API credentials.
    ```bash
    bash setup.sh
    ```
    If you prefer to create the configuration file manually, you can do so by creating a file named `api.conf` in the `/opt/wp-server` directory with the following content:
    ```
    API_KEY={YOUR_API_KEY}
    API_URL={YOUR_API_URL}
    ```

## Usage
To see the list of available commands, run the script with no arguments:
```bash
wp-server
```

## Commands

### `restart <service>`
This command restarts a specified service on the server.

**Usage:**
```bash
wp-server restart <service>
```

**Available Services:**
*   `php`: Restarts all PHP-FPM versions.
*   `nginx` or `web`: Restarts the Nginx web server.
*   `mysql` or `db`: Restarts the MySQL database server.
*   `redis`: Restarts the Redis server.

**Example:**
```bash
# Restart the PHP service
wp-server restart php
```

### `timeout [-s <seconds>]`
This command sets the PHP `max_execution_time` and Nginx `fastcgi_read_timeout` for the current site.

**Usage:**
```bash
wp-server timeout [-s <seconds>]
```

**Options:**
*   `-s, --set <seconds>`: (Optional) Specify the timeout value in seconds. If this option is not provided, the script will attempt to read the existing value from the site's `.user.ini` file. If no value is found, it will prompt the user to enter one.

**Examples:**
```bash
# Set the timeout to 300 seconds
wp-server timeout -s 300

# Run in interactive mode to view the current timeout or set a new one
wp-server timeout
```

### `max-upload [-m <MB>]`
This command sets the PHP `upload_max_filesize` and `post_max_size`, as well as Nginx `client_max_body_size` for the current site.

**Behavior:**
*   The `.user.ini` file's `upload_max_filesize` value is authoritative. If it exists, that value will be used for Nginx configuration without modifying `.user.ini`.
*   If `.user.ini` does not exist or does not contain `upload_max_filesize`, the command will prompt for a value (or use the `-m` flag) and create/update the `.user.ini` file.
*   When writing to `.user.ini`, the command sets:
    *   `upload_max_filesize = <MB>M`
    *   `post_max_size = <MB+2>M` (always 2 MB higher than upload_max_filesize)
*   The Nginx configuration is written to: `/etc/nginx/sites-available/<site>/server/client_max_body_size.conf`
*   After updating configurations, Nginx is validated with `nginx -t` before restarting PHP and Nginx services.

**Usage:**
```bash
wp-server max-upload [-m <MB>]
```

**Options:**
*   `-m, --mb <MB>`: (Optional) Specify the upload size in megabytes. If this option is not provided, the script will attempt to read the existing value from the site's `.user.ini` file. If no value is found, it will prompt the user to enter one.

**Examples:**
```bash
# Set the upload size to 256 MB
wp-server max-upload -m 256

# Run in interactive mode to view the current upload size or set a new one
wp-server max-upload
```

### `cache <sub-command>`
This command group is for managing the site's cache. These commands require a WordPress management plugin to be active.

**Usage:**
```bash
wp-server cache <sub-command>
```

**Available Sub-commands:**
*   `status`: Displays the status of the Nginx page cache and the object cache.
*   `purge-page`: Purges the Nginx page cache for the entire site.
*   `purge-object`: Flushes the object cache (equivalent to `wp cache flush`).

**Example:**
```bash
# Purge the Nginx page cache
wp-server cache purge-page
```

### `version` or `-v`
Displays the current version of the `wp-server` script.

**Usage:**
```bash
wp-server version
```

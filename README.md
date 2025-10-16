# wp-server
`wp-server` is a command-line tool for managing common server and site-specific operations on a SpinupWP server. It provides "site" users with simple CLI tools for tasks such as restarting services, managing cache, and adjusting PHP timeouts.

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

### `max-upload [-m <megabytes>]`
This command sets the maximum upload size for PHP and Nginx on the current site.

**Behavior:**
*   If `.user.ini` contains `upload_max_filesize`, that value is authoritative and will be used for Nginx `client_max_body_size`.
*   The script will ensure `post_max_size` is set to `upload_max_filesize + 2 MB` (updating `.user.ini` if necessary).
*   Nginx configuration uses lowercase `m` and includes a semicolon (e.g., `client_max_body_size 256m;`).
*   Configuration is written to `/etc/nginx/sites-available/${current_site}/server/client_max_body_size.conf`.

**Usage:**
```bash
wp-server max-upload [-m <megabytes>]
```

**Options:**
*   `-m, --mb <megabytes>`: (Optional) Specify the upload size in megabytes. If this option is not provided, the script will attempt to read the existing value from the site's `.user.ini` file. If no value is found, it will prompt the user to enter one.

**Examples:**
```bash
# Set the max upload size to 256 MB
wp-server max-upload -m 256

# Run in interactive mode to view the current upload size or set a new one
wp-server max-upload
```

### `cache <sub-command>`
This command group is for managing the site's cache. These commands are only available if the site has the SpinupWP plugin active.

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

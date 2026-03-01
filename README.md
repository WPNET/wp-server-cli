# wp-server
`wp-server` is a command-line tool for managing common server and site-specific operations. It provides "site" users with simple CLI tools for tasks such as restarting services, managing caches, and adjusting PHP and web server settings.

## Features

- **Service Management**: Restart PHP, Nginx, MySQL, and Redis services
- **PHP Configuration**: Set timeout, memory limit, max upload size, and max input variables
- **Web Server Configuration**: Configure Nginx settings for upload size and timeouts
- **Cache Management**: Purge page and object caches (requires SpinupWP plugin)
- **PHP FPM Pool Configuration**: All PHP settings are written directly to PHP-FPM pool config files for the site user

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

## PHP Configuration

All PHP configuration changes made by this tool are written directly to the PHP-FPM pool configuration file located at:
```
/etc/php/{php_version}/fpm/pool.d/{site_user}.conf
```

The tool automatically detects the PHP version in use by determining the site user from the home directory ownership and finding the corresponding PHP-FPM pool configuration file. After making changes, the PHP service is automatically restarted to apply the new settings.

**Note:** This tool no longer uses `.user.ini` files for PHP configuration. If you have existing `.user.ini` files, you can safely remove them using the `remove-user-ini` command.

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
*   `-s, --set <seconds>`: (Optional) Specify the timeout value in seconds. If this option is not provided, you will be prompted to enter one.

**PHP Configuration:**
The timeout value is written to `/etc/php/{php_version}/fpm/pool.d/{site_user}.conf` as `php_admin_value[max_execution_time]`.

**Nginx Configuration:**
The timeout value is written to `/etc/nginx/sites-available/{site_name}/location/fastcgi-timeout.conf`.

**Examples:**
```bash
# Set the timeout to 300 seconds
wp-server timeout -s 300

# Run in interactive mode to set a new timeout
wp-server timeout
```

### `max-upload [-m <megabytes>]`
This command sets the maximum upload size for PHP and Nginx on the current site.

**Usage:**
```bash
wp-server max-upload [-m <megabytes>]
```

**Options:**
*   `-m, --mb <megabytes>`: (Optional) Specify the upload size in megabytes. If this option is not provided, you will be prompted to enter one.

**PHP Configuration:**
The upload settings are written to `/etc/php/{php_version}/fpm/pool.d/{site_user}.conf`:
*   `php_admin_value[upload_max_filesize] = {value}M`
*   `php_admin_value[post_max_size] = {value + 2}M`

**Nginx Configuration:**
The upload size is written to `/etc/nginx/sites-available/{site_name}/server/client-max-body-size.conf`.

**Examples:**
```bash
# Set the max upload size to 256 MB
wp-server max-upload -m 256

# Run in interactive mode to set a new upload size
wp-server max-upload
```

### `max-input-vars [-v <count>]`
This command sets the PHP `max_input_vars` setting for the current site. This determines the maximum number of input variables that may be accepted (useful for forms with many fields).

**Usage:**
```bash
wp-server max-input-vars [-v <count>]
```

**Options:**
*   `-v <count>`: (Optional) Specify the max input variables count. If this option is not provided, you will be prompted to enter one.

**PHP Configuration:**
The setting is written to `/etc/php/{php_version}/fpm/pool.d/{site_user}.conf` as `php_admin_value[max_input_vars]`.

**Examples:**
```bash
# Set max input vars to 5000
wp-server max-input-vars -v 5000

# Run in interactive mode
wp-server max-input-vars
```

### `memory-limit [-m <megabytes>]`
This command sets the PHP `memory_limit` for the current site. This determines the maximum amount of memory a script may consume.

**Usage:**
```bash
wp-server memory-limit [-m <megabytes>]
```

**Options:**
*   `-m <megabytes>`: (Optional) Specify the memory limit in megabytes. If this option is not provided, you will be prompted to enter one.

**PHP Configuration:**
The setting is written to `/etc/php/{php_version}/fpm/pool.d/{site_user}.conf` as `php_admin_value[memory_limit]`.

**Examples:**
```bash
# Set memory limit to 256 MB
wp-server memory-limit -m 256

# Run in interactive mode
wp-server memory-limit
```

### `remove-user-ini`
This command removes the `.user.ini` file from the webroot if it exists. This can be used to clean up old configuration files after migrating to PHP FPM pool configuration.

**Usage:**
```bash
wp-server remove-user-ini
```

**Example:**
```bash
wp-server remove-user-ini
```

### `cache <sub-command>`
This command group is for managing the site's cache. These commands are only available if the site has the Cache Control plugin active.

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

### `-v` or `--version`
Displays the current version of the `wp-server` script.

**Usage:**
```bash
wp-server -v
wp-server --version
```

**Note:** The version is also displayed at the top of the help text when you run `wp-server` without any arguments.

# wp-server
 WP Server - Server Management

```
# Login as root or a sudo user
cd /opt
git clone git@github.com:wpnet/wp-server.git
cd wp-server

# Create the api.conf file and populate with API_KEY and API_URL:
echo "API_KEY={YOUR_API_KEY}" >> api.conf
echo "API_URL={YOUR_API_URL}" >> api.conf

# Or, just run setup.sh and follow the prompts
# If 'api.conf' doesn't exist, it will be created and populated
# with API_KEY & API_URL from user prompts
bash setup.sh

# The user specified during set up can now login and run:
wp-server restart <service_name>
wp-server timeout

# Run with no arguments for help
wp-server
Usage:    wp-server <command>

Commands:
  restart <service>      Restart a service
  timeout [-s <seconds>] Set PHP and Nginx timeouts for the current site

Services for 'restart':
  PHP:          php (restarts all runtime versions)
  Database:     db | mysql
  Web server:   web | nginx
```

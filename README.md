# wp-restart
 WP Server - Restart services

```
# Login as root or a sudo user
cd /opt
git clone git@github.com:wpnet/wp-restart.git
cd wp-restart

# Create the api.conf file and populate with API_KEY and API_URL:
echo "API_KEY={YOUR_API_KEY}" >> api.conf
echo "API_URL={YOUR_API_URL}" >> api.conf

# Or, just run setup.sh and follow the prompts
# If 'api.conf' doesn't exist, it will be created and populated
# with API_KEY and API_URL from user prompts
bash setup.sh

# The user specified during set up can now login and run:
wp-restart <service_name>

# Run with no arguments for help
wp-restart
Usage:    wp-restart <service>
Services: PHP:          php (restarts all runtime versions)
          Database:     db | mysql
          Web server:   web | nginx
```

# wp-restart
 WP Server - Restart services

```
# login as root or a sudo user
cd /opt
git clone git@github.com:wpnet/wp-restart.git
cd wp-restart

# Create the api.conf file and populate with API_KEY and API_URL:
nano api.conf

# Or run:
echo "API_KEY={YOUR_API_KEY}" >> api.conf
echo "API_URL={YOUR_API_URL}" >> api.conf

# Example:
echo "API_KEY=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" >> api.conf
echo "API_URL=https://api.spinupwp.app/v1/servers" >> api.conf

# run setup.sh and follow the prompts
bash setup.sh

# login as the user specified during set up and run:
wp-restart <service_name>

# Run with no arguments for help
wp-restart
Usage:    wp-restart <service>
Services: PHP:          php (restarts all runtime versions)
          Database:     db | mysql
          Web server:   web | nginx
```

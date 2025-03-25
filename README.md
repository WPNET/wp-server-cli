# wp-restart
 WP Server - Restart services

```
# login as root or a sudo user
cd /opt
git clone git@github.com:wpnet/wp-restart.git
cd wp-restart
# Create the api.conf file and populate with API_KEY and API_URL:
nano api.conf
# or run:
echo "API_KEY={YOUR_API_KEY}" >> api.conf
echo "API_URL={YOUR_API_URL}" >> api.conf
# example:
echo "API_KEY=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" >> api.conf
echo "API_URL=https://api.spinupwp.app/v1/servers" >> api.conf
# run setup.sh and follow the prompts
bash setup.sh
```

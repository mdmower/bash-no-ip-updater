Bash No-IP Updater
------------------

A bash script to update the IP address of [No-IP](https://www.noip.com/) hostnames. Supports multiple hostname updates and log rotation (see `config_sample`). Interprets [No-IP protocol responses](https://www.noip.com/integrate/response) and follows client guidelines.

__Prerequisites__

* `bash`
* `curl` or `wget`
* `sed`
* GNU `coreutils`
* `gzip` (optional, for log rotation)

__Usage__

1. Copy `config_sample` to `config` and update the variables
2. Make the script executable (`chmod +x noipupdater.sh`)
3. Run it (`./noipupdater.sh`)

Location of config file can optionally be specified by passing parameter `-c`. For example,  
`./noipupdater.sh -c /path/to/config`

__Automation__

Include the script in your cron file (`crontab -e`):

Run script once each day at 5:30am:  
`30 5 * * * /path/to/noipupdater.sh`

Run the script every fifteen minutes:  
`*/15 * * * * /path/to/noipupdater.sh`

Note: If the cron job doesn't execute correctly, try these suggestions:

1. Add this line to your crontab: `SHELL=/bin/bash`
2. Remove the `.sh` extension

Forked from the [Simple Bash No-IP Updater by AntonioCS](https://github.com/AntonioCS/no-ip.com-bash-updater)

2013 © Matthew D. Mower  
2012 © AntonioCS

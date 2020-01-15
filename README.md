# Zabbix Template: Rclone Sync

This script logs [rclone sync](https://rclone.org/commands/rclone_sync/) tasks to Zabbix.

## Requirements
* Rclone
* Zabbix-Sender

## How to Use

1. Download the scripts to `/etc/zabbix/scripts/`

  ```bash
  mkdir -p /etc/zabbix/scripts
  cd /etc/zabbix/scripts
  curl -O https://raw.githubusercontent.com/sebastian13/zabbix-templates/master/rclone/scripts/rclone-sync.sh
  curl -O https://raw.githubusercontent.com/sebastian13/zabbix-templates/master/rclone/scripts/rclone-discovery.pl
  chmod +x rclone-sync.sh rclone-discovery.pl
  ``` 

2. Upload the template **zbx\_template\_rescript-rclone** to Zabbix Server and assign it to a host

3. Run the script

### Examples

```bash
/etc/zabbix/scripts/rclone-sync.sh [source] [destination]
```

Running as cronjob, I'm reccomending [chronic from moreutils](http://manpages.ubuntu.com/manpages/xenial/man1/chronic.1.html)

```bash
26 3 * * * chronic /etc/zabbix/scripts/rclone-sync.sh [source] [destination]
```

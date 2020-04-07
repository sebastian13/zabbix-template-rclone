#!/bin/bash
set -e

LOGDIR="/var/log/rclone"
LOGFILE="$LOGDIR/`date +\%Y-\%m-\%d-\%T`-rclone.log"
ZBX_SCRIPTS="/etc/zabbix/scripts"

#
# Define various output colors

cecho () {
  local _color=$1; shift
  # If running via cron, don't use colors.
  if tty -s
  then
  	echo -e "$(tput setaf $_color)$@$(tput sgr0)"
  else
  	echo $1
  fi
}
black=0; red=1; green=2; yellow=3; blue=4; pink=5; cyan=6; white=7;

#
# Checking Input

if [ ! $# -eq 2 ]
then
	echo
	cecho $red "Error: Arguments missing"
	cecho $red "Usage: rclone-sync.sh [source:sourcepath] [dest:destpath]"
	echo
	exit 1
else
	SOURCE=$1
	DEST=$2
fi

#
# Checking Requirements

if ! `systemctl is-active --quiet zabbix-agent`
then
	echo
	cecho $red "Error: Zabbix-Agent is not running."
	echo
	exit 1
fi
if ! `command -v pip3 >/dev/null 2>&1`
then
	cecho $red "Please install python3-pip."
	echo
	exit 1
fi
if ! `python3 -c 'import humanfriendly' >/dev/null 2>&1`
then
	cecho $red "Could not import python3 humanfriendly!"
	cecho $red "Please run 'pip3 install humanfriendly'."
	echo
	exit 1
fi
if [ ! -f "$ZBX_SCRIPTS/rclone-discovery.pl" ]
then
	echo
	cecho $red "Zabbix Script rclone-discovery.pl missing. For instructions visit:"
	cecho $red "https://github.com/sebastian13/zabbix-templates/tree/master/rclone"
	echo
	exit 1
fi

mkdir -p $LOGDIR

#
# Running Discovery

echo
cecho $yellow "Running Zabbix Discovery:"

DISCOVERY=$($ZBX_SCRIPTS/rclone-discovery.pl $SOURCE $DEST)
echo "$DISCOVERY" | python -m json.tool

zabbix_sender \
	--config /etc/zabbix/zabbix_agentd.conf \
	--key "rclone.sync.discovery" \
	--value "$DISCOVERY"

#
# Running Rclone

echo
cecho $yellow "Running rclone sync:"
rclone sync $SOURCE $DEST \
	--stats 360m \
	--stats-log-level NOTICE \
	2>&1 | tee $LOGFILE

#
# Read Logfile

echo
cecho $yellow "Running Logfile Parsing:"

TIME=$(stat -c '%015Y' $LOGFILE)
arr=()

RLOG_TB=$(cat $LOGFILE | grep '^Transferred:.*Bytes' | awk '{print $2}' \
		| python3 -c 'import sys; import humanfriendly; print (humanfriendly.parse_size(sys.stdin.read(), binary=True))' )
echo "Transferred Bytes: $RLOG_TB"
arr+=("- rclone.sync.transbytes.[$SOURCE.$DEST] $TIME $RLOG_TB")

RLOG_ER=$(cat $LOGFILE | grep '^Errors:' | awk '{print $2}')
echo "Errors:            $RLOG_ER"
if [ -n "$RLOG_ER" ]; then
	arr+=("- rclone.sync.errors.[$SOURCE.$DEST] $TIME $RLOG_ER")
fi

RLOG_CH=$(cat $LOGFILE | grep '^Checks:' | awk '{print $2}')
echo "Checks:            $RLOG_CH"
arr+=("- rclone.sync.checks.[$SOURCE.$DEST] $TIME $RLOG_CH")

RLOG_TF=$(cat $LOGFILE | grep '^Transferred:' | tail -n1  | awk '{print $2}')
echo "Transferred Files: $RLOG_TF"
arr+=("- rclone.sync.transfiles.[$SOURCE.$DEST] $TIME $RLOG_TF")

RLOG_ET=$(cat $LOGFILE | grep '^Elapsed time:' | awk '{print $3}')
echo "Elapsed Time:      $RLOG_ET"
RLOG_ET_h=$(echo $RLOG_ET | cut -s -d "h" -f 1)
#if [ -z "$RLOG_ET_h" ]; then RLOG_ET_h=0; fi
echo "Elapsed Hours:     $RLOG_ET_h"
RLOG_ET_m=$(echo $RLOG_ET | cut -s -d "m" -f 1 | cut -d "h" -f 2)
#if [ -z "$RLOG_ET_m" ]; then RLOG_ET_m=0; fi
echo "Elapsed Minutes:   $RLOG_ET_m"
RLOG_ET_s=$(echo $RLOG_ET | cut -s -d "s" -f 1 | cut -d "m" -f 2 | cut -d. -f1 )
echo "Elapsed Seconds:   $RLOG_ET_s"
RLOG_ET_SUM=$((RLOG_ET_h * 3600 + RLOG_ET_m * 60 + RLOG_ET_s ))
echo "Elapsed Total Sec: $RLOG_ET_SUM"
arr+=("- rclone.sync.time.[$SOURCE.$DEST] $TIME $RLOG_ET_SUM")

#
# Send Everything to Zabbix

send-to-zabbix () {
	for ix in ${!arr[*]}; do printf "%s\n" "${arr[$ix]}"; done | zabbix_sender --config /etc/zabbix/zabbix_agentd.conf --with-timestamps --input-file -
}

echo
cecho $yellow "Sending to Zabbix:"
printf '%s\n' "${arr[@]}"
send-to-zabbix || { cecho $red "[ERROR] Sending or processing of some items failed. Will wait one minute before trying again..."; sleep 60; send-to-zabbix; }


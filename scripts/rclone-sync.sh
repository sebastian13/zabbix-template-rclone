#!/bin/bash
set -e

LOGFILE="/var/log/rclone.log"

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


if [ ! $# -eq 2 ]
then
	echo
	cecho $red "Error: Arguments missing"
	cecho $red "Usage: rclone-sync.sh [source:sourcepath] [dest:destpath]"
	echo
	exit 1
fi

echo
cecho $yellow "Running rclone sync:"
rclone sync $1 $2 \
	--verbose \
	--stats 360m \
	--stats-log-level NOTICE \
	2>&1 | tee ${LOGFILE}

echo
cecho $yellow "Running Zabbix Discovery:"
# Change to working directory
cd "$(dirname "$0")"
DISCOVERY=$(./rclone-discovery.pl $1 $2)

zabbix_sender \
	--config /etc/zabbix/zabbix_agentd.conf \
	--key "rclone.sync.discovery" \
	--value "$DISCOVERY"

echo
cecho $yellow "Running Zabbix Extraction:"

TIME=$(stat -c '%015Y' $LOGFILE)
arr=()

RLOG_TB=$(tail -n6 ${LOGFILE} | grep '^Transferred:.*Bytes' | awk '{print $2}' \
		| python3 -c 'import sys; import humanfriendly; print (humanfriendly.parse_size(sys.stdin.read(), binary=True))' )
echo "Transferred Bytes: $RLOG_TB"
arr+=("- rclone.sync.transbytes.[$1.$2] $TIME $RLOG_TB")

RLOG_ER=$(tail -n6 $LOGFILE | grep '^Errors:' | awk '{print $2}')
echo "Errors:            $RLOG_ER"
arr+=("- rclone.sync.errors.[$1.$2] $TIME $RLOG_ER")

RLOG_CH=$(tail -n6 $LOGFILE | grep '^Checks:' | awk '{print $2}')
echo "Checks:            $RLOG_CH"
arr+=("- rclone.sync.checks.[$1.$2] $TIME $RLOG_CH")

RLOG_TF=$(tail -n6 $LOGFILE | grep '^Transferred:' | tail -n1  | awk '{print $2}')
echo "Transferred Files: $RLOG_TF"
arr+=("- rclone.sync.transfiles.[$1.$2] $TIME $RLOG_TF")

RLOG_ET=$(tail -n6 $LOGFILE | grep '^Elapsed time:' | awk '{print $3}')
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
arr+=("- rclone.sync.time.[$1.$2] $TIME $RLOG_ET_SUM")

echo
cecho $yellow "Sending to Zabbix:"

send-to-zabbix () {
	for ix in ${!arr[*]}; do printf "%s\n" "${arr[$ix]}"; done | zabbix_sender --config /etc/zabbix/zabbix_agentd.conf --with-timestamps --input-file -
}
send-to-zabbix || { cecho $red "[ERROR] Sending or processing of some items failed. Will wait one minute before trying again..."; sleep 60; send-to-zabbix; }
echo

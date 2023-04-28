#!/bin/bash
# Dynamic deps
MODULE_MD5SUM_MODULES_SH=e9fb7bd46882b73e0f76bba5d408a7bf
MODULE_MD5SUM_DOTENV_SH=1c61bbfd10ed98dbb6c41442227f2a53

[ "$BASH_VERSION" ] || (echo "Bash required"; exit 1)

set -euo pipefail

SEND_ALERT_SH_SOURCE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# shellcheck source=../includes/modules.sh
source "$SEND_ALERT_SH_SOURCE_DIR/../includes/modules.sh" -- send-alert.sh
# shellcheck source=../includes/dotenv.sh
source "$SEND_ALERT_SH_SOURCE_DIR/../includes/dotenv.sh" --

#to log in file. $1 is log level. $2 is message
log() {
	if [ $# -gt 1 ];
	then
		printf '%s %s %s\n' "$(date)" "$1" "$2" >> "$BACKUP_LOG_FULL_PATH";
	else
		printf '%s %s %s\n' "$(date)" "INFO" "$1" >> "$BACKUP_LOG_FULL_PATH";
	fi
}

check_preriquisite()
{
  if [ -z "$REPLICATION_ROOT_PATH" ] || [ -z "$REPLICATION_DATA_DIR" ] || [ -z "$BACKUP_DIR" ] || [ -z "$LATEST_DIR" ] || [ -z "$HISTORY_DIR" ] || [ -z "$PERSISTENT_DATA_DIR" ] || [ -z "$SECURITY_DATA" ] || [ -z "$TOPOLOGY_DATA" ] || [ -z "$MEASUREMENT_DATA" ] || [ -z "$ALARM_DATA" ];
  then
    echo "ERROR .env was not exported correctly or replication variables values are not correct : exiting setup..."  
    exit 1
  fi
}

#main code
#The backup failure cause should be available
if [ "$EUID" -ne 0 ]
    then echo "Please run as root"
    exit 255
fi
importAddons
loadEnv
checkEnvironment
check_preriquisite

if [ -f "$BACKUP_ALERT_SCRIPT_PATH" ] && [ -f "$BACKUP_LOG_FULL_PATH" ]
then
	# execute client script file
	"$BACKUP_ALERT_SCRIPT_PATH" "$1" || :
	log "External client script was executed with the message key : $1"
fi


#!/bin/bash
# Dynamic deps
MODULE_MD5SUM_MODULES_SH=e9fb7bd46882b73e0f76bba5d408a7bf
MODULE_MD5SUM_DOTENV_SH=1c61bbfd10ed98dbb6c41442227f2a53

[ "$BASH_VERSION" ] || (echo "Bash required"; exit 1)

set -euo pipefail

BACKUPS_SH_SOURCE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# shellcheck source=../includes/modules.sh
source "$BACKUPS_SH_SOURCE_DIR/../includes/modules.sh" -- backup.sh
# shellcheck source=../includes/dotenv.sh
source "$BACKUPS_SH_SOURCE_DIR/../includes/dotenv.sh"

umask 022



#lock error message
LOCK_ERROR_MESSAGE="The lock file is already being used ! The Snapshot process will now stop ..."

#backup setup config
REPLICA_ROOT_MOUNT_PATH=/dev
REPLICA_VOLUME_GROUP=replica_vg
REPLICA_SNAPSHOT_LVM_NAME=replica_snapshot
REPLICA_LIVE_LVM_NAME=replica_live
REPLICA_SNAPSHOT_PATH=$REPLICA_ROOT_MOUNT_PATH/$REPLICA_VOLUME_GROUP/$REPLICA_SNAPSHOT_LVM_NAME
SNAPSHOT_MOUNT=/mnt/snapshot/
LOCK_FILE_PATH=/var/lock/fms_backup.lock

#to log in file. $1 is log level. $2 is message
#$BACKUP_LOG_FULL_PATH is set in config file
log() 
{
	if [ $# -gt 1 ];
	then
		printf '%s %s %s\n' "$(date)" "$1" "$2" >> "$BACKUP_LOG_FULL_PATH";
	else
		printf '%s %s %s\n' "$(date)" "INFO" "$1" >> "$BACKUP_LOG_FULL_PATH";
	fi
}

#$SNAPSHOT_MOUNT is already create by setup.sh
#$REPLICA_SNAPSHOT_PATH is already create by setup.sh
remove_snap()
{
        umount $SNAPSHOT_MOUNT
        lvremove $REPLICA_SNAPSHOT_PATH -f
}

#send alert to the client
send_alert()
{
    if [ -f "$ALERT_SCRIPT_PATH" ]
    then
        if [ $# -gt 0 ];
        then
            $ALERT_SCRIPT_PATH "$1"
        else
            $ALERT_SCRIPT_PATH
        fi
    fi
}

#$1 is the failed message key that should be send to the client
#here is the message key mapping :
#"logical volume creation failed" <=> lvm_failed
#"volume mount failed"  <=> mnt_failed
#"rsync failed" <=> rsync_failed
#"backup copy failed" <=> copy_failed
#"unmount or deletion of replica_snapshot failed"<=> remove_failed
#"log path doesn't exist" <=> log_failed
#"$MAX_BACKUP_ALLOW is not set or equal 0" <=> nb_backup_allow_failed
die()
{
    log "ERROR" "Error during backup, rolling back"
    log "ERROR" "$1"
    #send alert to the client
    send_alert "$1" || :
    remove_snap || :
    exit 1
}

update_number_of_stored_backup_files()
{
        nb_backup_files_stored="`( ls "${REPLICATION_ROOT_PATH}${BACKUP_DIR}${HISTORY_DIR}" || : ) | wc -l`"
}


add_new_backup()
{
    DIR=$(date +"%Y.%m.%d.%T")
    (
        mkdir -p "${REPLICATION_ROOT_PATH}${BACKUP_DIR}${HISTORY_DIR}" &&
        cp -al "${REPLICATION_ROOT_PATH}${BACKUP_DIR}${LATEST_DIR}" "${REPLICATION_ROOT_PATH}${BACKUP_DIR}${HISTORY_DIR}/$DIR"
    ) || die "copy_failed"
    log "New backup created: $DIR"
    log "New backup file $DIR was added in ${REPLICATION_ROOT_PATH}${BACKUP_DIR}${HISTORY_DIR}"
}

get_oldest_backup_file()
{
        mapfile -t backup_files < <(ls "${REPLICATION_ROOT_PATH}${BACKUP_DIR}${HISTORY_DIR}")
        oldest_backup_file=""
        for i in ${!backup_files[*]}
        do
                content=${backup_files[$i]}
                if [ -z "$oldest_backup_file" ]
                then
                        oldest_backup_file=$content
                elif [ "$content" \< "$oldest_backup_file" ]
                then
                        oldest_backup_file=$content
                fi
        done
}

store_new_backup()
{
    update_number_of_stored_backup_files
    log "nb backups stored: $nb_backup_files_stored"
    log "max backup allow: $MAX_BACKUP_ALLOW"
    while [[ $nb_backup_files_stored -ge $MAX_BACKUP_ALLOW ]]
    do
        get_oldest_backup_file
        # :? used here to avoid substition to rm -rf /
        rm -rf "${REPLICATION_ROOT_PATH}${BACKUP_DIR}${HISTORY_DIR}/${oldest_backup_file:?}"
        log "stored backup file $oldest_backup_file was deleted"
        update_number_of_stored_backup_files
    done
    add_new_backup
}


other_check()
{
    #check if all the .env variables are set 
    if [ -z "$REPLICATION_ROOT_PATH" ] || [ -z "$REPLICATION_DATA_DIR" ] || [ -z "$BACKUP_DIR" ] || [ -z "$LATEST_DIR" ] || [ -z "$HISTORY_DIR" ] || [ -z "$PERSISTENT_DATA_DIR" ] || [ -z "$SECURITY_DATA" ] || [ -z "$TOPOLOGY_DATA" ] || [ -z "$MEASUREMENT_DATA" ] || [ -z "$ALARM_DATA" ];
    then
        echo "ERROR .env was not exported correctly or replication variables values are not correct : exiting backup"  
        exit 1
    fi
    #log file check
    mkdir -p "${MASTER_ROOT_PATH}${LOG_DIR}${BACKUP_DIR}" || die "log_failed";
    touch "$BACKUP_LOG_FULL_PATH" || die "log_failed"

    #alert scripts check
    if [ ! -f "$BACKUP_ALERT_SCRIPT_PATH" ] || [ ! -f "$ALERT_SCRIPT_PATH" ]
    then
        log "INFO" "As client or alert script was not provided, client alert is disabled"
    fi
    #check number of backup allowed
    if [[ -z $MAX_BACKUP_ALLOW ]] || [[ $MAX_BACKUP_ALLOW -eq 0 ]]
    then
        send_alert "nb_backup_allow_failed"
        log "ERROR" "The number of backup allowed was not set or is equal 0... Process aborted"
        exit 1
    fi
}

#main code
main()
{
  other_check
  exec 500>$LOCK_FILE_PATH
  if ! flock -n 500; then
	  log "ERROR" "$LOCK_ERROR_MESSAGE";
	  exit 1
  fi
  log "The lockFile has been taken. The Snapshot process can start ..."

  log "Backup process started..."
  backup_process_start_time=$(date +%s)
  lvcreate -n $REPLICA_SNAPSHOT_LVM_NAME -l 10%ORIGIN -s ${REPLICA_VOLUME_GROUP}/${REPLICA_LIVE_LVM_NAME} &>> "$BACKUP_LOG_FULL_PATH" ||
        die "lvm_failed"

  mount -t xfs -o ro,nouuid $REPLICA_SNAPSHOT_PATH $SNAPSHOT_MOUNT &>> "$BACKUP_LOG_FULL_PATH" ||
        die "mnt_failed"

  log "Copy from snapshot to latest backup started.."
  SECONDS=0
  ionice rsync -a -8 -v --delete --force --exclude '/logs' --exclude '/data/prometheus' --progress --numeric-ids --stats $SNAPSHOT_MOUNT "${REPLICATION_ROOT_PATH}${BACKUP_DIR}${LATEST_DIR}" &>> "$BACKUP_LOG_FULL_PATH" ||
        die "rsync_failed"

  copy_from_snapshot_duration=$SECONDS
  log "End of copy from snapshot to latest backup"
  log "Copy from snapshot to latest backup successfully finished in $((copy_from_snapshot_duration / 60)) minutes and $((copy_from_snapshot_duration % 60)) seconds"
  remove_snap || die "remove_failed"

  log "Copy from latest backup to backup history started.."
  SECONDS=0
  store_new_backup || die "store_new_backup_failed"
  
  copy_from_backup_duration=$SECONDS
  log "End of copy from latest backup to backup history"
  log "Copy from latest backup to backup history successfully finished in $((copy_from_backup_duration / 60)) minutes and $((copy_from_backup_duration % 60)) seconds"
  backup_process_end_time=$(date +%s)
  backup_process_duration="$((backup_process_end_time-backup_process_start_time))"
  log "Backup process successfully finished in $((backup_process_duration / 60)) minutes and $((backup_process_duration % 60)) seconds"
}

if [ "$EUID" -ne 0 ]
    then echo "Please run as root"
    exit 255
fi
importAddons
loadEnv
checkEnvironment
main 2>&1 | tee -a "$BACKUP_LOG_FULL_PATH"

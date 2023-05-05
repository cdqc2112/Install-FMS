#!/bin/bash
# Dynamic deps
MODULE_MD5SUM_MODULES_SH=e9fb7bd46882b73e0f76bba5d408a7bf
MODULE_MD5SUM_DOTENV_SH=1c61bbfd10ed98dbb6c41442227f2a53

[ "$BASH_VERSION" ] || (echo "Bash required"; exit 1)

set -euo pipefail

EXPORT_SH_SOURCE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# shellcheck source=../includes/modules.sh
source "$EXPORT_SH_SOURCE_DIR/../includes/modules.sh" -- export.sh
# shellcheck source=../includes/dotenv.sh
source "$EXPORT_SH_SOURCE_DIR/../includes/dotenv.sh"

if [ "$EUID" -ne 0 ]
    then echo "Please run as root"
    exit 255
fi

umask 022

function help() {
    echo "Usage: export.sh [--get-latest-files-from <server>] | [--push-latest-files-to <server>] [--snapshot] [--to-primary <server>] [--to-replica <server>]" >&2
    echo "" >&2

    echo "   --get-latest-files-from <user@server>   fetch latest measurement files on a primary server using the given ssh credential" >&2
    echo "   --push-latest-files-to <user@server>    push latest measurement files to a primary server using the given ssh credential" >&2
    echo "   --to-primary <user@server>              push whole data to a primary server using the given ssh credential" >&2
    echo "   --to-replica <user@server>              push whole data to a replica server using the given ssh credential" >&2
    echo "   --snapshot                              push whole data using a snapshot (required if replication is running)" >&2
    echo "   --file-threads n                        when pushing whole, uses that number of threads for measures transfert - 0 to disable (default 6)" >&2

    exit 1
}

function argumentRequired() {
    if [ "$#" -lt 2 ]; then
        echo "ERROR: Wrong command. $1 requires an argument" >&2
        exit 255
    fi
    if [ -z "$2" ]; then
        echo "ERROR: Value for $1 cannot be empty" >&2
        exit 255
    fi
}

RSYNC_TO_PRIMARY=""
RSYNC_TO_REPLICA=""
RSYNC_SNAPSHOT=""
LATEST_FROM=""
LATEST_TO=""

typeset -i LATEST_DELAY=240
typeset -i PARALLEL_FILES=6

while [ $# != 0 ]; do
    case "$1" in
        "--to-primary")
            argumentRequired "$@"
            shift
            RSYNC_TO_PRIMARY="$1"
            shift
            ;;
        "--to-replica")
            argumentRequired "$@"
            shift
            RSYNC_TO_REPLICA="$1"
            shift
            ;;
        "--file-threads")
            argumentRequired "$@"
            shift
            PARALLEL_FILES="$1"
            shift
            ;;
        "--push-latest-files-to")
            argumentRequired "$@"
            shift
            LATEST_TO="$1"
            shift
            ;;
        "--get-latest-files-from")
            argumentRequired "$@"
            shift
            LATEST_FROM="$1"
            shift
            ;;
        "--latest-delay")
            argumentRequired "$@"
            shift
            LATEST_DELAY="$1"
            shift
            ;;
        "--snapshot") 
            RSYNC_SNAPSHOT=1
            shift
            ;;
        *)
            help
            ;;
    esac
done

if [ -z "$RSYNC_TO_PRIMARY$RSYNC_TO_REPLICA$LATEST_FROM$LATEST_TO" ]; then
    help
fi

#backup setup config
REPLICA_ROOT_MOUNT_PATH=/dev
REPLICA_VOLUME_GROUP=replica_vg
REPLICA_SNAPSHOT_LVM_NAME=replica_snapshot
REPLICA_LIVE_LVM_NAME=replica_live
REPLICA_SNAPSHOT_PATH=$REPLICA_ROOT_MOUNT_PATH/$REPLICA_VOLUME_GROUP/$REPLICA_SNAPSHOT_LVM_NAME
SNAPSHOT_MOUNT=/mnt/snapshot/
LOCK_FILE_PATH=/var/lock/fms_backup.lock

#$SNAPSHOT_MOUNT is already create by setup.sh
#$REPLICA_SNAPSHOT_PATH is already create by setup.sh
SNAP_CREATED=
remove_snap()
{
    if [ "$SNAP_CREATED" ]; then
        SNAP_CREATED=
        (
            trap -- '' SIGINT SIGTERM SIGTSTP
            
            umount "$SNAPSHOT_MOUNT" || /bin/true
            if ! lvremove "$REPLICA_SNAPSHOT_PATH" -f 500<&- ; then
                echo "Failed to remove snapshot" >&2
            else
                echo "Snapshot removed" >&2
            fi
        )
    fi
}

die()
{
    echo "ERROR:" "$@" >&2
    #send alert to the client
    remove_snap
    exit 1
}

importAddons
loadEnv
checkEnvironment

#check if all the .env variables are set 
if [ -z "$REPLICATION_ROOT_PATH" ] || [ -z "$REPLICATION_DATA_DIR" ] || [ -z "$BACKUP_DIR" ] || [ -z "$LATEST_DIR" ] || [ -z "$HISTORY_DIR" ] || [ -z "$PERSISTENT_DATA_DIR" ] || [ -z "$SECURITY_DATA" ] || [ -z "$TOPOLOGY_DATA" ] || [ -z "$MEASUREMENT_DATA" ] || [ -z "$ALARM_DATA" ];
then
    echo "ERROR .env was not exported correctly or replication variables values are not correct : exiting export"
    exit 1
fi

if [ "$RSYNC_TO_PRIMARY$RSYNC_TO_REPLICA" ]; then
    if [ "$RSYNC_SNAPSHOT" ]; then
        echo "Creating snapshot for data export" >&2
        exec 500>$LOCK_FILE_PATH
        
        if ! flock -n 500; then
            echo "ERROR: Unable to acquire lock. Check permission and running backup process" >&2;
            exit 1
        fi
        echo "The lockFile has been taken. The export process can start ..." >&2

        SECONDS=0
        echo "Creating snapshot" >&2
        # Set snap_create here to allow removal of dandling snapshot in case it already exists
        SNAP_CREATED=1
        lvcreate -n $REPLICA_SNAPSHOT_LVM_NAME -l 10%ORIGIN -s ${REPLICA_VOLUME_GROUP}/${REPLICA_LIVE_LVM_NAME} 500<&- || die "lvm_failed"
        mount -t xfs -o ro,nouuid $REPLICA_SNAPSHOT_PATH $SNAPSHOT_MOUNT || die "mnt_failed"

        RSYNC_SOURCE="$SNAPSHOT_MOUNT"
    else
        echo "Assuming local data is idle for data export" >&2
        RSYNC_SOURCE="$REPLICATION_ROOT_PATH$REPLICATION_DATA_DIR/"
    fi
    # -a archive
    # -8 preserve file names
    # --delete remove unwanted files on target
    # --force  force removal of non empty dirs
    # --numeric-ids don't map uid/gid
    # -W whole file transfert
    # Dropped:
    # --stats give some file-transfer stats

    RSYNC_ARGS=(-a -W -8 --delete --force --exclude '/logs' --exclude '/data/prometheus' --numeric-ids)

    # Use a pipe for child synchronization (xargs will let child finishing later than itself)
    SYNCPIPE=$(mktemp -u)
    mkfifo "$SYNCPIPE"

    (
        exec 501> "$SYNCPIPE"

        (if [ "$RSYNC_TO_REPLICA" ]; then
            # Reopen fifo in write as 502
            echo "Exporting data content to replica $RSYNC_TO_REPLICA" >&2
            if [ "$PARALLEL_FILES" != 0 ]; then
                RSYNC_FILES_ARGS=("--rsync-path=mkdir -p '$REPLICATION_ROOT_PATH$REPLICATION_DATA_DIR$PERSISTENT_DATA_DIR$FILE_DATA/' && rsync")
                (find "$RSYNC_SOURCE$PERSISTENT_DATA_DIR$FILE_DATA" -maxdepth 1 -mindepth 1 -printf '%f\0' ) | \
                        xargs -0 -r -n 1 -P "$PARALLEL_FILES" -I {} \
                            rsync "${RSYNC_ARGS[@]}" "${RSYNC_FILES_ARGS[@]}" "$RSYNC_SOURCE$PERSISTENT_DATA_DIR$FILE_DATA/{}" "$RSYNC_TO_REPLICA:$REPLICATION_ROOT_PATH$REPLICATION_DATA_DIR$PERSISTENT_DATA_DIR$FILE_DATA/"
            fi

            if ! rsync "${RSYNC_ARGS[@]}" --exclude '/.*'  "$RSYNC_SOURCE" "$RSYNC_TO_REPLICA:$REPLICATION_ROOT_PATH$REPLICATION_DATA_DIR"; then
                printf "  rsync to replica failed" >&501
                exit 1
            fi
            
        fi) &
        REPLICA_PID=$!

        (if [ "$RSYNC_TO_PRIMARY" ]; then
            # Reopen fifo in write as 502
            echo "Exporting data content to primary $RSYNC_TO_PRIMARY" >&2

            if [ "$PARALLEL_FILES" != 0 ]; then
                RSYNC_FILES_ARGS=("--rsync-path=mkdir -p '$ROOT_PATH$PERSISTENT_DATA_DIR$FILE_DATA/' && rsync")
                (find "$RSYNC_SOURCE$PERSISTENT_DATA_DIR$FILE_DATA" -maxdepth 1 -mindepth 1 -printf '%f\0' ) | \
                        xargs -0 -r -n 1 -P "$PARALLEL_FILES" -I {} \
                            rsync "${RSYNC_ARGS[@]}" "${RSYNC_FILES_ARGS[@]}" "$RSYNC_SOURCE$PERSISTENT_DATA_DIR$FILE_DATA/{}" "$RSYNC_TO_PRIMARY:$ROOT_PATH$PERSISTENT_DATA_DIR$FILE_DATA/"
            fi

            if ! rsync "${RSYNC_ARGS[@]}" --exclude '/.*' --exclude '/data/**/recovery.conf' "$RSYNC_SOURCE" "$RSYNC_TO_PRIMARY:$ROOT_PATH"; then
                printf "  rsync to primary failed" >&501
                exit 1
            fi
        fi) &
        PRIMARY_PID=$!

        if [ "$RSYNC_TO_REPLICA" ]; then
            if ! wait "$REPLICA_PID" ; then
                exit
            fi
        fi
        
        if [ "$RSYNC_TO_PRIMARY" ]; then
            if ! wait "$PRIMARY_PID"; then
                exit
            fi
        fi
        
        printf "done" >&501
    ) &

    trap "remove_snap" EXIT INT TERM

    SYNCPIPERESULT="`(trap -- '' SIGINT SIGTERM SIGTSTP ; cat "$SYNCPIPE" )`"
    rm -- "$SYNCPIPE"

    remove_snap
    # Release the lock
    exec 500<&-

    if [ "$SYNCPIPERESULT" != "done" ]; then
        if [ "$SYNCPIPERESULT" ]; then
            printf "Rsync failed : %s\n" "$SYNCPIPERESULT"
            exit 1
        else
            # Killed
            exit 255
        fi
    fi
fi

if [ "$LATEST_FROM" ]; then
    echo "Synchronizing latest measurement files from remote primary ($LATEST_DELAY minutes). Site switch can start from now." >&2
    ( ssh "$LATEST_FROM" cd "$ROOT_PATH$PERSISTENT_DATA_DIR$FILE_DATA" '&&' '(' find . -type f -mmin "-$LATEST_DELAY" -print0 \| tar -cf - --null --files-from /dev/stdin ')' | tar -C "$REPLICATION_ROOT_PATH$REPLICATION_DATA_DIR$PERSISTENT_DATA_DIR$FILE_DATA" -xf - ) || exit 1
fi

if [ "$LATEST_TO" ]; then
    echo "Synchronizing latest measurement files to remote primary ($LATEST_DELAY minutes). Site switch can start from now." >&2

    ( cd "$REPLICATION_ROOT_PATH$REPLICATION_DATA_DIR$PERSISTENT_DATA_DIR$FILE_DATA" && (find . -type f -mmin "-$LATEST_DELAY" -print0 | tar -cf - --null --files-from /dev/stdin ) | ssh "$LATEST_TO" tar -C "$ROOT_PATH$PERSISTENT_DATA_DIR$FILE_DATA" -xf - ) || exit 1
fi

echo "INFO: process successfull"

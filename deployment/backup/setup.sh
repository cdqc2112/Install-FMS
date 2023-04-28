#!/bin/bash
# Dynamic deps
MODULE_MD5SUM_MODULES_SH=e9fb7bd46882b73e0f76bba5d408a7bf
MODULE_MD5SUM_DOTENV_SH=1c61bbfd10ed98dbb6c41442227f2a53

[ "$BASH_VERSION" ] || (echo "Bash required"; exit 1)

set -euo pipefail

MODULE_INCLUDE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# shellcheck source=../includes/modules.sh
source "$MODULE_INCLUDE_DIR/../includes/modules.sh" -- setup.sh
# shellcheck source=../includes/dotenv.sh
source "$MODULE_INCLUDE_DIR/../includes/dotenv.sh"

umask 022

#backup setup config
# Remark: could be made part of .env ?
REPLICA_ROOT_MOUNT_PATH=/dev
REPLICA_VOLUME_GROUP=replica_vg
REPLICA_LIVE_LVM_NAME=replica_live
REPLICA_BACKUP_LVM_NAME=replica_backups
SNAPSHOT_MOUNT=/mnt/snapshot/
LOCK_FILE_PATH=/var/lock/fms_backup.lock

check_preriquisite()
{
  if [ -z "$REPLICATION_ROOT_PATH" ] || [ -z "$REPLICATION_DATA_DIR" ] || [ -z "$BACKUP_DIR" ] || [ -z "$LATEST_DIR" ] || [ -z "$HISTORY_DIR" ] || [ -z "$PERSISTENT_DATA_DIR" ] || [ -z "$SECURITY_DATA" ] || [ -z "$TOPOLOGY_DATA" ] || [ -z "$MEASUREMENT_DATA" ] || [ -z "$ALARM_DATA" ];
  then
    echo "ERROR .env was not exported correctly or replication variables values are not correct : exiting setup..."  
    exit 1
  fi
}

hasArgument() {
  local arg="$1"
  local i
  shift
  for i in "$@"; do
    if [ "$i" = "$arg" ]; then
      return 0
    fi
  done
  return 1
}

die() {
  echo "ERROR " "$1" >&2
  exit 1
}



#main code
if [ "$EUID" -ne 0 ]
    then echo "Please run as root"
    exit 255
fi
#Load addons from deployment dir
cd .. && importAddons && cd -
loadEnv
checkEnvironment
check_preriquisite

if ! hasArgument "--no-partition" "$@" ;then
  lsblk
  read -rep "Enter the name of the disk to be used (will be parted): " disk
  if ! hasArgument "--has-label"  "$@" ; then
    parted "$REPLICA_ROOT_MOUNT_PATH/$disk" mklabel gpt
  fi
  parted -m -s "$REPLICA_ROOT_MOUNT_PATH/$disk" unit mib mkpart primary 1 100% || die "Can't create partition, verify that your disk is empty before running setup.sh script. Exiting..."
  parted -s "$REPLICA_ROOT_MOUNT_PATH/$disk" set 1 lvm on
  sleep 2
  lsblk
  read -rep "Enter the name of the newly created partition on the $disk disk: " disk1
  if ! pvcreate "$REPLICA_ROOT_MOUNT_PATH/$disk1"; then
              echo "ERROR" "Error during volume creation, deleting previous partition."
              parted "$REPLICA_ROOT_MOUNT_PATH/$disk" rm 1
              exit 1
  fi
  vgcreate "$REPLICA_VOLUME_GROUP" "$REPLICA_ROOT_MOUNT_PATH/$disk1"
  lvcreate  -l 25%VG -n $REPLICA_LIVE_LVM_NAME $REPLICA_VOLUME_GROUP
  lvcreate  -l 50%VG -n $REPLICA_BACKUP_LVM_NAME $REPLICA_VOLUME_GROUP
  mkfs.xfs $REPLICA_ROOT_MOUNT_PATH/$REPLICA_VOLUME_GROUP/$REPLICA_LIVE_LVM_NAME || die "on file systems creation, check if file system replica_live and replica_backups already exist before running this script. Exiting..."
  mkfs.xfs $REPLICA_ROOT_MOUNT_PATH/$REPLICA_VOLUME_GROUP/$REPLICA_BACKUP_LVM_NAME || die "on file systems creation, check if file system replica_live and replica_backups already exist before running this script. Exiting..."

  mkdir -p "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}";
  mkdir -p "${REPLICATION_ROOT_PATH}${BACKUP_DIR}";

  echo "$REPLICA_ROOT_MOUNT_PATH/$REPLICA_VOLUME_GROUP/$REPLICA_LIVE_LVM_NAME    ${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}    xfs     defaults,nofail,noatime        0 0" | tee /etc/fstab -a
  echo "$REPLICA_ROOT_MOUNT_PATH/$REPLICA_VOLUME_GROUP/$REPLICA_BACKUP_LVM_NAME ${REPLICATION_ROOT_PATH}${BACKUP_DIR}             xfs     defaults,nofail,noatime        0 0" | tee /etc/fstab -a
  mount -a -t xfs
fi

#Replica live directories
mkdir -p "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${SECURITY_DATA}";
if [ -d "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${SECURITY_DATA}" ] && [ ! -d "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${SECURITY_DATA}/v9.5" ] && [ ! -d "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${SECURITY_DATA}/v13" ]; then
    if [ -d "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${SECURITY_DATA}/tmp" ]; then 
      mv "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${SECURITY_DATA}/tmp" "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${SECURITY_DATA}/v9.5"
    else
      (mv "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${SECURITY_DATA}" "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${SECURITY_DATA}95" &&
      mkdir -p "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${SECURITY_DATA}" &&
      mv "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${SECURITY_DATA}95" "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${SECURITY_DATA}/v9.5") || 
      (echo "Failed during 'Security' replicated data transit to v9.5 folder. The data folder has been renamed to ${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${SECURITY_DATA}95. You shall run : ";
      echo "mkdir -p ${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${SECURITY_DATA}";
      echo "mv ${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${SECURITY_DATA}95 ${ROOT_PATH}${PERSISTENT_DATA_DIR}${SECURITY_DATA}/v9.5")
    fi
fi
chown -R 70:0 "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${SECURITY_DATA}"

mkdir -p "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}";
if [ -d "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}" ] && [ ! -d "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}/v9.5" ] && [ ! -d "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}/v13" ]; then
    (mv "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}" "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}95" &&
    mkdir -p "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}" &&
    mv "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}95" "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}/v9.5") || 
    (echo "Failed during 'Topology' replicated data transit to v9.5 folder. The data folder has been renamed to ${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}95. You shall run : ";
      echo "mkdir -p ${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}";
      echo "mv ${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}95 ${ROOT_PATH}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}/v9.5")
fi
chown -R 70:0 "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${TOPOLOGY_DATA}"

mkdir -p "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${MEASUREMENT_DATA}";
chown -R 999:0 "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${MEASUREMENT_DATA}";
mkdir -p "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${ALARM_DATA}";
chown -R 999:0 "${REPLICATION_ROOT_PATH}${REPLICATION_DATA_DIR}${PERSISTENT_DATA_DIR}${ALARM_DATA}";

# Run script from addons
executeInstallFunctions "${ADDON_CREATE_REPLICA_DIRECTORIES_FUNCTIONS[@]}"


#Replica backups directories
mkdir -p "${REPLICATION_ROOT_PATH}${BACKUP_DIR}${LATEST_DIR}";
mkdir -p "${REPLICATION_ROOT_PATH}${BACKUP_DIR}${HISTORY_DIR}";

#Replica log directories (nfs)
mkdir -p "${MASTER_ROOT_PATH}${LOG_DIR}${BACKUP_DIR}";

mkdir -p $SNAPSHOT_MOUNT
touch $LOCK_FILE_PATH
echo "Partitions all set"
lsblk -f

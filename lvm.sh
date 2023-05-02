#!/bin/bash

# Basic setup script for docker assuming inet connectivity.

. ./multi-os.sh

set -euo pipefail


if [ -z ${FMS_STANDALONE_VOLUME+x} ]; then
    exit 0
fi

if [ "$FMS_STANDALONE_VOLUME" != true ]; then
    exit 0
fi

if [ "$FMS_ROLE" != primary ]; then
    exit 0
fi

echo "Checking LVM setup"

if grep /dev/replica_vg/ /etc/fstab ; then
    echo "LVM setup already done"
    exit 0
fi

which nvme > /dev/null 2>&1 || installPackage nvme-cli
which jq > /dev/null 2>&1 || installPackage jq
which pvcreate > /dev/null 2>&1 || installPackage lvm2

function findNvmeDevice() {
        local device="$1"
        if [ -z "$device" ]; then
                return 0
        fi

        local allDevices="`nvme list --output-format=json | jq -r .Devices[].DevicePath `"
        local cand
        for cand in $allDevices; do
                if nvme id-ctrl -v "$cand" -H | grep -E "\"$device|\"/dev/$device" > /dev/null; then
                        echo "$cand"
                        return 0
                fi
        done

        echo "Device not found $device amongst $allDevices" >&2

        return 0
}

function retry5() {
        local command=("$@");
        local len=${#command[@]}
        local n=0

        until [ "$n" -ge 5 ]
        do
                "${command[@]}" && return 0
                n=$((n+1)) 
                sleep 2
                echo "Retrying $1...${command[$len-2]}" >&2
        done

        echo "$1...${command[$len-2]} failed on all retries, exiting..." >&2
        return 1;
}


device="$FMS_STANDALONE_VOLUME_ID"
targetDevice=""
while [ -z "$targetDevice" ]; do
        targetDevice="`findNvmeDevice "$device"`"
        if [ -z "$targetDevice" ]; then
                echo "Waiting for $device to come"
                sleep 2
        fi
done

# Creating and mounting volumes
DISKID="${targetDevice#/dev/}"

echo "Setting up disk $DISKID"
parted /dev/${DISKID} mklabel msdos
parted -m -s /dev/${DISKID} unit mib mkpart primary 1 100%
sleep 0.1
while [ ! -e /dev/${DISKID}p1 ]; do
    echo "Waiting for /dev/${DISKID}p1  to come up"
    sleep 1
done
pvcreate /dev/${DISKID}p1
vgcreate replica_vg /dev/${DISKID}p1
retry5 lvcreate -l 25%VG -n replica_live replica_vg
retry5 lvcreate -l 50%VG -n replica_backups replica_vg
mkfs.xfs /dev/replica_vg/replica_live
mkfs.xfs /dev/replica_vg/replica_backups

mkdir -p /opt/fms/solution
mkdir -p /opt/fms/replication/backup
printf "\n/dev/replica_vg/replica_live     /opt/fms/solution            xfs    defaults,nofail     0 0\n" >> /etc/fstab
printf "\n/dev/replica_vg/replica_backups  /opt/fms/replication/backup  xfs    defaults,nofail     0 0\n" >> /etc/fstab
mount -a -t xfs
mkdir -p /mnt/snapshot

# Utile uniquement <= 7.5.2
ln -s /opt/fms/master /opt/fms/solution

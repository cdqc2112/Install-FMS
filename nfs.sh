#! /bin/bash
set -euxo pipefail
source /etc/os-release

if grep nfs4 /etc/fstab ; then
    echo "Nfs already mounted"
    exit 0
fi
if [  -f "$WORKINGDIR/.offline" ];then
    cd $WORKINGDIR/nfs
    if [ "$ID_LIKE" = "debian" ]; then
        dpkg -i *.deb
    else
        rpm -iUvh *.rpm
    cd $WORKINGDIR
    fi
else
    if [ "$ID_LIKE" = "debian" ]; then
        apt install -y nfs-common
    else
        yum install -y nfs-utils
    fi
fi
if [ -f "$WORKINGDIR/.multinode" ]; then
    DEP_DIR="/opt/fms/solution"
    mkdir -p $DEP_DIR
elif [ -f "$WORKINGDIR/.replica" ]; then
    DEP_DIR="/opt/fms/master"
    mkdir -p $DEP_DIR
else
    DEP_DIR="/opt/fms/solution"
    mkdir -p $DEP_DIR
fi
clear
echo "A NFS share is required to hold the FMS application files"
read -p 'Enter the NFS share path (x.x.x.x:/share): ' SHARE
echo $SHARE     ${DEP_DIR}  nfs4 auto,nofail,noatime,nolock,intr,tcp,actimeo=1800  0 0 | tee /etc/fstab -a
mount -av
echo "$(date): NFS client installed and ${DEP_DIR} mounted" >> $LOGFILE
export DEP_DIR
touch $WORKINGDIR/.nfs
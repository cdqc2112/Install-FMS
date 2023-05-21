#! /bin/bash

if [  -f "$WORKINGDIR/.offline" ];then
        cd $WORKINGDIR/nfs
        if [ "$FMS_INSTALLER" = "apt" ]; then
            dpkg -i *.deb
        else
            rpm -iUvh *.rpm
        cd $WORKINGDIR
        fi
    else
        $FMS_INSTALLER install -y nfs-common
        $FMS_INSTALLER install -y nfs-utils
    fi
    if [ -f "$WORKINGDIR/.singlenode" ]; then
        DEP_DIR="/opt/fms/master"
        mkdir -p $DEP_DIR/cer
    if [ -f "$WORKINGDIR/.replica" ]; then
        DEP_DIR="/opt/fms/master"
        mkdir -p $DEP_DIR
    else
        DEP_DIR="/opt/fms/solution"
        mkdir -p $DEP_DIR
    fi
    clear
    echo "A NFS share is required to hold the FMS application files"
    read -p 'Enter the NFS share path (x.x.x.x:/share): ' SHARE
    if [ -f "$WORKINGDIR/.replica" ]; then
        echo $SHARE     ${DEP_DIR}  nfs4 auto,nofail,noatime,nolock,intr,tcp,actimeo=1800  0 0 | tee /etc/fstab -a
    else
        echo $SHARE     ${DEP_DIR}  nfs4 auto,nofail,noatime,nolock,intr,tcp,actimeo=1800  0 0 | tee /etc/fstab -a
    fi
    mount -av
    echo "$(date): NFS client installed and ${DEP_DIR} mounted" >> $LOGFILE
    touch $WORKINGDIR/.nfs
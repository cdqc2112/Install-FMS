#! /bin/bash

if [ "$UID" != 0 ]; then
    echo "Run as root"
    exit 1
fi

clear

WORKINGDIR=${PWD}
LOGFILE=$WORKINGDIR/install.log

export LOGFILE
export WORKINGDIR

touch $LOGFILE
source /etc/os-release

if [ "$ID_LIKE" = "debian" ]; then
    FMS_INSTALLER=apt
else
    FMS_INSTALLER=yum
fi

echo "Script to install Docker and setup LVM on workers and replica server"
echo
# Installation options
if [ -f "$WORKINGDIR/.offline" ];then
    echo "Offline installation"
elif [ -f "$WORKINGDIR/.online" ];then 
    echo "Online installation"
else
    read -r -p 'Is this an offline installation? [y/N] ' response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
            touch $WORKINGDIR/.offline
        else
            touch $WORKINGDIR/.online 
        fi
fi
read -r -p 'Is this a replica node [y/N] ' response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
         touch $WORKINGDIR/.replica
    fi
# Install NFS client
if [ -f "$WORKINGDIR/.nfs" ]; then
    echo "NFS done"
else
    ./nfs.sh
    # if [  -f "$WORKINGDIR/.offline" ];then
    #     cd $WORKINGDIR/nfs
    #     if [ "$FMS_INSTALLER" = "apt" ]; then
    #         dpkg -i *.deb
    #     else
    #         rpm -iUvh *.rpm
    #     cd $WORKINGDIR
    #     fi
    # else
    #     $FMS_INSTALLER install -y nfs-common
    #     $FMS_INSTALLER install -y nfs-utils
    # fi
    # if [ -f "$WORKINGDIR/.replica" ]; then
    #     DEP_DIR="/opt/fms/master"
    #     mkdir -p $DEP_DIR
    # else
    #     DEP_DIR="/opt/fms/solution"
    #     mkdir -p $DEP_DIR
    # fi
    # read -p 'Enter the NFS share path (x.x.x.x:/share): ' SHARE
    # if [ -f "$WORKINGDIR/.replica" ]; then
    #     echo $SHARE     ${DEP_DIR}  nfs4 auto,nofail,noatime,nolock,intr,tcp,actimeo=1800  0 0 | tee /etc/fstab -a
    # else
    #     echo $SHARE     ${DEP_DIR}  nfs4 auto,nofail,noatime,nolock,intr,tcp,actimeo=1800  0 0 | tee /etc/fstab -a
    # fi
    # mount -av
    # echo "$(date): NFS client installed and ${DEP_DIR} mounted" >> $LOGFILE
    # touch $WORKINGDIR/.nfs
fi
if [ ! -f "${DEP_DIR}/deployment/.env" ]; then
    read -n 1 -r -s -p $'Cannot find .env file. Make sure NFS share is mounted and required installation files are present on /opt/fms/master"\n'
    exit
fi
clear
# Backup and replica volumes
if [ -f "$WORKINGDIR/.rep" ]; then
    read -n 1 -r -s -p $'Solution and backup volume LVM setup already done. Press enter to continue...\n'
else
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        /opt/fms/master/deployment/backup/./setup.sh
        echo "$(date): Backup and replica volume created" >> $LOGFILE
        touch $WORKINGDIR/.rep
    fi
fi
# Offline Installation
if [ -f "$WORKINGDIR/.offline" ];then
    while true; do
        if [ ! -f "$WORKINGDIR/images.tgz" ];
        then
            echo
            read -n 1 -r -s -p $'Required images.tgz file is missing. Copy the file in ${WORKINGDIR} and press enter to continue...\n'
            echo
            continue
        fi
    break
done
fi
# Install packages
if [ -f "$WORKINGDIR/.packages" ];then
    echo "Packages installed"
else
    # Offline
    if [ -f "$WORKINGDIR/.offline" ];then
        cd $WORKINGDIR/packages
        if [ "$FMS_INSTALLER" = "apt" ]; then
            dpkg -i *.deb
        else
            rpm -iUvh *.rpm
        cd $WORKINGDIR
        fi
    echo "$(date): Packages installed" >> $LOGFILE
    touch $WORKINGDIR/.packages
    else
    # Online
        $FMS_INSTALLER install -y \
                dos2unix \
                bash-completion \
                rsync \
                openssl \
                lvm2
    echo "$(date): Packages installed" >> $LOGFILE
    touch $WORKINGDIR/.packages
    fi
fi
# Firewall
if [ -f "$WORKINGDIR/.firewall" ];then
    echo "Firewall done"
else
    if [ "$FMS_INSTALLER" = "apt" ]; then
        ufw allow 2377/tcp
        ufw allow 7946/tcp
        ufw allow 7946/udp
        ufw allow 4789/udp
        ufw allow 500/udp
        ufw allow 4500/udp
        ufw allow nfs
    else
        firewall-cmd --permanent --add-port=2377/tcp
        firewall-cmd --permanent --add-port=7946/tcp
        firewall-cmd --permanent --add-port=7946/udp
        firewall-cmd --permanent --add-port=4789/udp
        firewall-cmd --permanent --add-port=500/udp
        firewall-cmd --permanent --add-port=4500/udp
        firewall-cmd --permanent --add-protocol 50
        firewall-cmd --permanent --add-protocol 51
        firewall-cmd --permanent --add-service="ipsec"
        firewall-cmd --permanent --add-service=nfs
        firewall-cmd --permanent --add-service=rpc-bind
        firewall-cmd --permanent --add-service=mountd
        firewall-cmd --reload
    fi
        touch $WORKINGDIR/.firewall
        echo "$(date): Firewall done" >> $LOGFILE
fi
# Uninstall previous Docker version
# $FMS_INSTALLER remove docker docker-engine docker.io containerd runc
if [ -f "$WORKINGDIR/.docker" ];then
    echo "Docker installed"
else
    $FMS_INSTALLER remove docker \
            docker-client \
            docker-client-latest \
            docker-common \
            docker-latest \
            docker-latest-logrotate \
            docker-logrotate \
            docker-engine \
            docker.io \
            containerd \
            podman \
            buildah \
            runc
    echo "$(date): Previous Docker version removed" >> $LOGFILE
    # Install Docker Ubuntu
    # offline
    if [ -f "$WORKINGDIR/.offline" ];then
        if [ "$FMS_INSTALLER" = "apt" ]; then
            cd $WORKINGDIR/docker/
            dpkg -i ./containerd.io_1.6.20-1_amd64.deb \
            ./docker-ce_20.10.24~3-0~ubuntu-jammy_amd64.deb \
            ./docker-ce-cli_20.10.24~3-0~ubuntu-jammy_amd64.deb \
            ./docker-buildx-plugin_0.10.4-1~ubuntu.22.04~jammy_amd64.deb \
            ./docker-compose-plugin_2.17.2-1~ubuntu.22.04~jammy_amd64.deb
            cd $WORKINGDIR
        else
            cd $WORKINGDIR/docker/
            $FMS_INSTALLER install -y *.rpm
            cd $WORKINGDIR
        fi
    else
    # online
        $FMS_INSTALLER -y update
        $FMS_INSTALLER -y install \
            ca-certificates \
            curl \
            gnupg
        mkdir -m 0755 -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo \
          "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        $FMS_INSTALLER -y update
        # Show Docker versions
        if [ "$FMS_INSTALLER" = "apt" ]; then
            $FMS_INSTALLER-cache madison docker-ce | awk '{ print $3 }'
            echo
            echo 'Copy the version string above'
            echo
            read -e -p 'Recommended version is 20.10.x. Paste it here: ' -i "5:20.10.24~3-0~ubuntu-jammy" VERSION_STRING
            $FMS_INSTALLER -y install \
            docker-ce=$VERSION_STRING \
            docker-ce-cli=$VERSION_STRING \
            containerd.io docker-buildx-plugin \
            docker-compose-plugin
        else
            $FMS_INSTALLER install -y yum-utils
            #RHEL
            #$FMS_INSTALLER-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
            #CentOS
            $FMS_INSTALLER-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            $FMS_INSTALLER list docker-ce --showduplicates | sort -r
            echo
            echo 'Copy the version string above (2nd column) starting at the first colon (:), up to the first hyphen'
            echo
            read -e -p 'Recommended version is 20.10.x. Paste it here: ' -i "20.10.24" VERSION_STRING
            $FMS_INSTALLER -y install \
            docker-ce-$VERSION_STRING \
            docker-ce-cli-$VERSION_STRING \
            containerd.io \
            docker-compose-plugin
        fi
    fi
    systemctl enable docker
    systemctl start docker
    usermod -aG docker $USER
    docker version
    # vm max count
    sysctl -w vm.max_map_count=262144
    echo 'vm.max_map_count=262144' | sudo tee --append /etc/sysctl.d/95-fms.conf > /dev/null
    sed -i 's/After=network-online.target\ docker.socket\ firewalld.service\ containerd.service/After=network-online.target\ docker.socket\ firewalld.service\ containerd.service\ local-fs.target\ remote-fs.target/g' /lib/systemd/system/docker.service
    systemctl daemon-reload
cat > /etc/docker/daemon.json <<EOF
{
    "log-driver":"json-file",
    "log-opts":{
        "max-size": "10M",
        "max-file": "10"
    }
}
EOF
    service docker restart
    touch $WORKINGDIR/.docker
    echo "$(date): Docker installed" >> $LOGFILE
fi
# Docker swarm join
if [ -f "$WORKINGDIR/.swarm" ];then
    read -n 1 -r -s -p $'Docker swarm join already done. Press enter to continue...\n'
else
    # Login to Dockerhub
    docker login
    echo "Joining swarm"
    echo 'Run this command on manager "docker swarm join-token worker"'
    read -p $'Paste the string from manager to join the swarm: ' JOIN
    $JOIN
    if test -f "$WORKINGDIR/.replica";then 
        echo "Set the label for replica"
        echo 'Run this command on manager "docker node update --label-add role=replica <nodeidOfReplicaServer>"'
    fi
    touch $WORKINGDIR/.swarm
    echo "$(date): Swarm joined" >> $LOGFILE
fi
if [ -f "$WORKINGDIR/.offline" ];then
    cd $WORKINGDIR/
    tar -xvf images.tgz
    cd $WORKINGDIR/images/
    for a in *.tar;do docker load -i $a;done
    cd $WORKINGDIR/
    rm -rf images.tgz
fi
#Backup
if [ -f "$WORKINGDIR/.replica" ];then
    printf '#!/bin/bash\ncd /opt/fms/master/deployment/backup && exec ./backup.sh > /dev/null 2>&1\n' > /etc/cron.daily/fms_backup
    chmod +x /etc/cron.daily/fms_backup
fi
exit
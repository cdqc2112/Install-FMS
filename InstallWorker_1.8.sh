#! /bin/bash
# InstallWorker - 1.8

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
echo "It requires at least 60GB on /var for Docker and a volume for solution and backups on the replica server"
echo "Master node must be ready before running this script"

read -r -p 'Is this a replica node [y/N] ' response

    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
         touch $WORKINGDIR/.replica
    fi

# Install NFS client

if test -f "$WORKINGDIR/.nfs"; then

    read -n 1 -r -s -p $'Solution and backup volume LVM setup already done. Press enter to continue...\n'

else

    $FMS_INSTALLER install -y nfs-common
    $FMS_INSTALLER install -y nfs-utils

    if test -f "$WORKINGDIR/.replica"; then
        mkdir -p /opt/fms/master
    else
        mkdir -p /opt/fms/solution
    fi
    
    read -p 'Enter the NFS share path (x.x.x.x:/share): ' SHARE

    if test -f "$WORKINGDIR/.replica"; then
        echo $SHARE     /opt/fms/master  nfs auto,nofail,noatime,nolock,intr,tcp,actimeo=1800 0 0 | tee /etc/fstab -a
    else
        echo $SHARE     /opt/fms/solution  nfs auto,nofail,noatime,nolock,intr,tcp,actimeo=1800 0 0 | tee /etc/fstab -a
    fi

    mount -av

    echo "$(date): NFS client installed and /opt/fms/master mounted" >> $LOGFILE
    touch $WORKINGDIR/.nfs

fi

if [ ! -f "/opt/fms/master/deployment/.env" ]; then

    read -n 1 -r -s -p $'Cannot find .env file. Make sure NFS share is mounted and required installation files are present on /opt/fms/master"\n'
    
    exit

fi

clear

# Backup and replica volumes

if test -f "$WORKINGDIR/.rep"; then

    read -n 1 -r -s -p $'Solution and backup volume LVM setup already done. Press enter to continue...\n'

else

    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        
        /opt/fms/master/deployment/backup/./setup.sh
        echo "$(date): Backup and replica volume created" >> $LOGFILE
        touch $WORKINGDIR/.rep   

    fi
fi

if test -f "$WORKINGDIR/.soft"; then

    read -n 1 -r -s -p $'Docker already installed. Press enter to continue...\n'

else

    # Install tools
    # offline
    if test -f "$WORKINGDIR/.offline";then
        cd $WORKINGDIR/packages
        dpkg -i bash-completion_2.11-5ubuntu1_all.deb
        dpkg -i dos2unix_7.4.2-2_amd64.deb
        dpkg -i openssl_3.0.2-0ubuntu1.8_amd64.deb
        dpkg -i rsync_3.2.7-0ubuntu0.22.04.2_amd64.deb
        cd $WORKINGDIR
    else
        # online
        $FMS_INSTALLER install -y \
                dos2unix \
                bash-completion \
                rsync \
                openssl
        # Firewall
        if [ "$FMS_INSTALLER" = "apt" ]; then
            ufw allow 2377
            ufw allow 7946
            ufw allow 4789
            ufw allow 443
            ufw allow 22
            ufw allow 61617
            ufw allow 500
            ufw allow 4500
        else
            firewall-cmd --zone=public --permanent --add-port=2377/tcp
            firewall-cmd --zone=public --permanent --add-port=7946/tcp
            firewall-cmd --zone=public --permanent --add-port=7946/udp
            firewall-cmd --zone=public --permanent --add-port=4789/udp
            firewall-cmd --zone=public --permanent --add-port=500/udp
            firewall-cmd --zone=public --permanent --add-port=4500/udp
            firewall-cmd --permanent --add-service="ipsec"
            firewall-cmd --reload
        fi
        # Uninstall previous Docker version
        # $FMS_INSTALLER remove docker docker-engine docker.io containerd runc
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
                  runc
        echo "$(date): Previous Docker version removed" >> $LOGFILE
    fi
    # Install Docker Ubuntu
    # offline
    if test -f "$WORKINGDIR/.offline";then
        if [ "$FMS_INSTALLER" = "apt" ]; then
            cd $WORKINGDIR/packages/
            dpkg -i ./containerd.io_1.6.20-1_amd64.deb \
            ./docker-ce_20.10.24~3-0~ubuntu-jammy_amd64.deb \
            ./docker-ce-cli_20.10.24~3-0~ubuntu-jammy_amd64.deb \
            ./docker-buildx-plugin_0.10.4-1~ubuntu.22.04~jammy_amd64.deb \
            ./docker-compose-plugin_2.17.2-1~ubuntu.22.04~jammy_amd64.deb
            cd $WORKINGDIR
        else
            cd $WORKINGDIR/packages/
            yum install *.rpm
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
            read -e -p 'Copy version above and paste here: ' -i "5:20.10.24~3-0~ubuntu-jammy" VERSION_STRING
            $FMS_INSTALLER -y install \
            docker-ce=$VERSION_STRING \
            docker-ce-cli=$VERSION_STRING \
            containerd.io docker-buildx-plugin \
            docker-compose-plugin
        else
            $FMS_INSTALLER install -y yum-utils
            $FMS_INSTALLER-config-manager \
                --add-repo \
                https://download.docker.com/linux/centos/docker-ce.repo
            $FMS_INSTALLER list docker-ce --showduplicates | sort -r
            read -e -p 'Copy version above and paste here: ' -i "20.10.24" VERSION_STRING
            $FMS_INSTALLER -y install \
            docker-ce-$VERSION_STRING \
            docker-ce-cli-$VERSION_STRING \
            containerd.io \
            docker-compose-plugin
        fi
        # Choose Docker version to install
        #CentOS 8
        #wget https://download.docker.com/linux/centos/8/x86_64/stable/Packages/docker-ce-20.10.23-3.el8.x86_64.rpm
        #yum install docker-ce-20.10.23-3.el8.x86_64.rpm
    fi
    systemctl enable docker
    systemctl start docker
    usermod -aG docker $USER
    docker version
    read -n 1 -r -s -p $'Press enter to continue...\n'
    clear
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
    touch $WORKINGDIR/.soft
    echo "$(date): Docker installed" >> $LOGFILE
fi

# Docker swarm join

if test -f "$WORKINGDIR/.swarm";then
    read -n 1 -r -s -p $'Docker swarm join already done. Press enter to continue...\n'
else

    # Login to Dockerhub
    clear
    docker login

    echo "Joining swarm"

    read -p $'Paste the string from manager to join the swarm: ' JOIN

    $JOIN

    echo "Set the label for replica node from manager node"
    echo "docker node update --label-add role=replica <nodeidOfReplicaServer>"

    touch $WORKINGDIR/.swarm
    echo "$(date): Swarm joined" >> $LOGFILE
fi
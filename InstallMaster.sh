#! /bin/bash
# InstallMaster - 1.27

if [ "$UID" != 0 ]; then
    echo "Run as root"
    exit 1
fi

clear

WORKINGDIR=${PWD}
LOGFILE=$WORKINGDIR/install.log

export LOGFILE
export WORKINGDIR

RED=`tput setab 1 setaf 7`
NC=`tput sgr0`

touch $LOGFILE
source /etc/os-release

if [ "$ID_LIKE" = "debian" ]; then
    FMS_INSTALLER=apt
else
    FMS_INSTALLER=yum
fi

function installPackage() {
    if [ "$FMS_INSTALLER" = "apt" ]; then
        apt install -y "$@"
    else
        yum install -y "$@"
    fi
}

echo -e "Script to install Docker and setup FMS on ${RED}Ubuntu${NC} or ${RED}CentOS${NC}"
echo
echo
# Solution and backup volume LVM
echo "Docker engine data"
echo
echo "Docker will require disk space on every nodes for the purpose of storing docker images, container logs and runtime temporary files."
echo
echo "It is advised to allocate a specific partition for the /var/lib/docker directory, with at least 60Gb."
echo "If no specific partition is used, this 60Gb will be consummed on the root partition, so the root partition"
echo "must be sized accordingly (increased by 60Gb from normal OS requirement)."
echo
echo "The usage intensity on this storage will not be related to the load applied to the server. A SSD class storage is recommanded."
echo
echo
echo "FMS data"
echo
echo "A dedicated disk volume is required for the FMS data, on the following two server nodes:"
echo
echo "     The only node in single-server architecture, when not using NFS"
echo "     Replica nodes in Replication or Cross-site redundancy architectures"
echo
echo "The disk must be visible at the OS level as a block device (ex: /dev/sdb)"
echo
echo "The required capacity and bandwidth for the disk depends on the FMS usage, please refer to the sizing guide for actual values."
echo
echo "The disk must not initially be partitionned, as the installation process includes a specific partitioning process using LVM."
echo
echo
read -r -p 'Is this an offline installation? [y/N] ' response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
    echo
    echo "Copy images.tgz file to $WORKINGDIR"
    echo
    touch $WORKINGDIR/.offline
fi

if test -f "$WORKINGDIR/.volume";then
    read -n 1 -r -s -p $'Solution and backup volume LVM setup already done. Press enter to continue...\n'
else
    echo "The storage can be a file system hosted on a local device, or network remote (NFS)."
    echo "When using a storage on a local device, the backup functionality can be installed, if volumes are created over LVM."
    echo 
    read -r -p 'Is this a single node with local volume storage? [y/N] ' response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
        touch $WORKINGDIR/.singlenode
        echo "This will create a single LVM to hold the FMS application files and backups"
        echo -e "A separated volume is required and will be ${RED}erased${NC}"
        lsblk
        read -rep "Confirm the disk to be used (will be partitioned): " -i "sdb" disk
        parted /dev/$disk mklabel msdos
        parted -m -s /dev/$disk unit mib mkpart primary 1 100%
        sleep 2
        lsblk
        read -rep "Confirm the newly created partition on the $disk disk: " -i "${disk}1" disk1
        pvcreate /dev/$disk1
        vgcreate replica_vg /dev/$disk1
        lvcreate -l 25%VG -n replica_live replica_vg
        lvcreate -l 50%VG -n replica_backups replica_vg
        mkfs.xfs /dev/replica_vg/replica_live
        mkfs.xfs /dev/replica_vg/replica_backups
        mkdir -p /opt/fms/solution
        mkdir -p /opt/fms/replication
        mkdir -p /opt/fms/replication/backup
        mkdir -p /mnt/snapshot
        echo /dev/replica_vg/replica_live  /opt/fms/solution xfs defaults,nofail 0 0  | tee /etc/fstab -a
        echo /dev/replica_vg/replica_backups /opt/fms/replication/backup xfs defaults,nofail 0 0  | tee /etc/fstab -a
        mount -avt xfs
        ln -s /opt/fms/solution /opt/fms/master
        mkdir -p /opt/fms/replication/backup/history
        mkdir -p /opt/fms/solution/cer
        lsblk
        touch $WORKINGDIR/.volume
        echo "$(date): replica_live replica_vg and replica_backups replica_vg created" >> $LOGFILE
    else
        Install NFS client
        $FMS_INSTALLER install -y nfs-common
        $FMS_INSTALLER install -y nfs-utils
        mkdir -p /opt/fms/solution
        echo "A NFS share is required to hold the FMS application files"
        read -p 'Enter the NFS share path (x.x.x.x:/share): ' SHARE
        echo $SHARE     /opt/fms/solution  nfs auto,nofail,noatime,nolock,intr,tcp,actimeo=1800 0 0 | tee /etc/fstab -a
        mount -av
        mkdir -p /opt/fms/solution/cer
        touch $WORKINGDIR/.volume
        touch $WORKINGDIR/.multinode
        echo "$(date): NFS client installed" >> $LOGFILE
    fi
fi

if test -f "$WORKINGDIR/.soft";then
    read -n 1 -r -s -p $'Docker already installed. Press enter to continue...\n'
else
    # Install tools
    # offline
    if test -f "$WORKINGDIR/.offline";then
        cd $WORKINGDIR/packages
        if [ "$FMS_INSTALLER" = "apt" ]; then
            dpkg -i *.deb
        else
            rpm -iUvh *.rpm
        cd $WORKINGDIR
        fi
    else
    # online
        $FMS_INSTALLER install -y \
                dos2unix \
                bash-completion \
                rsync \
                openssl
    fi
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
        ufw allow nfs
    else
        firewall-cmd --zone=public --permanent --add-port=2377/tcp
        firewall-cmd --zone=public --permanent --add-port=7946/tcp
        firewall-cmd --zone=public --permanent --add-port=7946/udp
        firewall-cmd --zone=public --permanent --add-port=4789/udp
        firewall-cmd --zone=public --permanent --add-port=500/udp
        firewall-cmd --zone=public --permanent --add-port=4500/udp
        firewall-cmd --zone=public --permanent --add-service="ipsec"
        firewall-cmd --zone=public --permanent --add-service=nfs
        firewall-cmd --zone=public --permanent --add-service=rpc-bind
        firewall-cmd --zone=public --permanent --add-service=mountd
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
    # Install Docker Ubuntu
    # offline
    if test -f "$WORKINGDIR/.offline";then
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
            $FMS_INSTALLER-config-manager \
                --add-repo \
                https://download.docker.com/linux/centos/docker-ce.repo
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

# Domain and Certificates
clear
if test -f "$WORKINGDIR/.certs";then
    read -n 1 -r -s -p $'Certificates already created. Press enter to continue...\n'
    DOMAIN=$(ls -tr|grep *.dom)
    DOMAIN="${DOMAIN::-4}"
else
    while true; do
    echo 'Enter the URL to access the FMS (ex.: fms.domain.com): '
    read DOMAIN
    touch $WORKINGDIR/$DOMAIN.dom
    if [ -z $DOMAIN ]; then
        echo "Error: No FQDN provided"
        echo "Usage: Provide a valid FQDN"
        continue
    fi
    break
    done

    #read -p 'Enter the URL to access the FMS (ex.: fms.domain.com): ' DOMAIN
    #if [ -z ${DOMAIN} ];then
    #    echo "Error: No FQDN name provided"
    #    echo "Usage: Provide a domain name as an argument"
    #    exit 1
    #fi
    
    read -r -p 'Do you have the certificate? [y/N] ' response
    
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
        echo "Copy certificate ${DOMAIN}.crt and private key ${DOMAIN}.key to folder $WORKINGDIR"
        echo
        echo
        touch $WORKINGDIR/.certs
    else
        read -r -p 'Do you want to generate a private key and a certificate request? [y/N] ' response

        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
            echo "Creation of a private key and a certificate request (csr) to submit to Certificate Authority (CA) to generate the certificate"
            read -e -p 'Enter the country name (2 letter code): ' -i "US" COUNTRY
            read -e -p 'Enter the state or province: ' -i "State" STATE
            read -e -p 'Enter the locality: ' -i "City" CITY
            export DOMAIN
            export COUNTRY
            export STATE
            export CITY
            ./csr.sh            
            echo
            echo "Copy this csr and submit to Certificate Authotity (ex.: Godaddy, Verisign, Let's Encrypt, ...)"
            echo
            cat ${DOMAIN}.csr
            echo
            echo "Wait until you get the certificate to continue"
            echo
            echo "Copy certificate ${DOMAIN}.crt when received from CA to folder $WORKINGDIR"
            touch $WORKINGDIR/.certs
        else
            read -r -p 'Do you want to generate a self-signed certificate? [y/N] ' response
    
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
                clear
                echo "rootCA.crt will be created in /opt/fms/solution/cer that will need to be installed in browser"
                read -n 1 -r -s -p $'or imported into Trusted Root Certification Authorities Press enter to continue...\n'
                echo
                read -e -p 'Enter the country name (2 letter code): ' -i "US" COUNTRY
                read -e -p 'Enter the state or province: ' -i "State" STATE
                read -e -p 'Enter the locality: ' -i "City" CITY
                export DOMAIN
                export COUNTRY
                export STATE
                export CITY
                ./selfSignedCert.sh
                echo "$(date): Certificate ${DOMAIN}.crt created" >> $LOGFILE
                touch $WORKINGDIR/.certs
            fi
        fi
    fi
fi
# Docker swarm init and node labels
if test -f "$WORKINGDIR/.swarm";then
    read -n 1 -r -s -p $'Docker swarm init and node labels already done. Press enter to continue...\n'
else

    # Login to Dockerhub
    docker login
    echo "Starting swarm"
    docker swarm init
    # Set node labels
    NODEID=$(docker node ls --format "{{.ID}}")
    docker node update --label-add endpoints=true $NODEID
    docker node update --label-add role=primary $NODEID
    touch $WORKINGDIR/.swarm
    echo "$(date): Node labels added and swarm started" >> $LOGFILE
fi
# Copy files to /opt/fms/solution
if test -f "$WORKINGDIR/.files";then
    read -n 1 -r -s -p $'Files already copied. Press enter to continue...\n'
else
    dos2unix deployment/docker-compose.yml
    dos2unix deployment/docker-compose-replication.yml
    dos2unix deployment/includes/*.sh
    dos2unix deployment/example.env
    dos2unix deployment/swarm.sh
    dos2unix deployment/backup/*.sh
    chmod +x deployment/swarm.sh deployment/backup/*.sh deployment/includes/*.sh
    cp -r deployment/ /opt/fms/solution
    cp *.crt *.key /opt/fms/solution/cer
    echo "$(date): Installation files copied to /opt/fms/solution" >> $LOGFILE
    # Adjust environment variables in .env file
    cp /opt/fms/solution/deployment/example.env /opt/fms/solution/deployment/.env
    sed -i 's/fms.<customer_domain>/'${DOMAIN}'/g' /opt/fms/solution/deployment/.env
    echo "$(date): DNS set in .env file" >> $LOGFILE
    sed -i 's/SNMP_IMPLEMENTATION_VERSION=0/SNMP_IMPLEMENTATION_VERSION=1/g' /opt/fms/solution/deployment/.env 
    # Create secrets
    docker secret create SERVER_CERT_SECRET /opt/fms/solution/cer/${DOMAIN}.crt
    docker secret create SERVER_CERT_KEY_SECRET /opt/fms/solution/cer/${DOMAIN}.key
    sed -i 's/SERVER_CERT_SECRET=/SERVER_CERT_SECRET=SERVER_CERT_SECRET/g' /opt/fms/solution/deployment/.env
    sed -i 's/SERVER_CERT_KEY_SECRET=/SERVER_CERT_KEY_SECRET=SERVER_CERT_KEY_SECRET/g' /opt/fms/solution/deployment/.env
    touch $WORKINGDIR/.files
fi
# Workers
if test -f "$WORKINGDIR/.multinode";then
    echo
    read -r -p 'Will there be worker nodes to set-up, including replica? [y/N] ' response
    echo
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
        echo "Upload and run InstallWorker script on worker nodes and use this token below to join them to this swarm"
        echo
        docker swarm join-token worker
        echo
        echo "When this is done, you can continue here and start the FMS"
        echo
    fi
    # Replica
    echo
    echo 'If Replica node is required, it must have joined the swarm before proceeding'
    read -r -p 'Will there be replica node to set-up? [y/N] ' response
    echo
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
        docker node ls
        echo
        read -p 'Enter the node ID of the replica server: ' RNODEID
        echo
        docker node update --label-add role=replica $RNODEID
        echo
        sed -i 's|MASTER_ROOT_PATH=/opt/fms/solution|MASTER_ROOT_PATH=/opt/fms/master|g' /opt/fms/solution/deployment/.env
        sed -i 's|REPLICATION_ENABLED=false|REPLICATION_ENABLED=true|g' /opt/fms/solution/deployment/.env
    else
        sed -i 's|MASTER_ROOT_PATH=/opt/fms/master|MASTER_ROOT_PATH=/opt/fms/solution|g' /opt/fms/solution/deployment/.env
        sed -i 's|REPLICATION_ENABLED=true|REPLICATION_ENABLED=false|g' /opt/fms/solution/deployment/.env
    fi
fi
echo
read -r -p 'Are you using GIS addon? [y/N] ' response
echo
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
    touch $WORKINGDIR/global.json
    cat > $WORKINGDIR/global.json <<EOF
    {
    "isCentralizedMode": true,
    "delayForSaveGraphMl": 500,
    "isGisEnabled": true
    }
EOF
else
    rm -rf /opt/fms/solution/deployment/gis.addon
fi
# Starting FMS
if test -f "$WORKINGDIR/.secrets";then
    read -n 1 -r -s -p $'Secrets already done. Press enter to continue...\n'
else
    touch $WORKINGDIR/.secrets
    cd /opt/fms/solution/deployment/
    ./swarm.sh --init-iam-users --fill-secrets --no-deploy >> secrets
    mv $WORKINGDIR/global.json /opt/fms/solution/config/topology_ui
    chmod -R 755 /opt/fms/solution/config/
    chown -R root /opt/fms/solution/config
    chmod -R ugo+rX,go-w /opt/fms/solution/config
fi
read -r -p 'Are you ready to start the FMS? [y/N] ' response
echo
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
    if test -f "$WORKINGDIR/.offline";then
        cd $WORKINGDIR/
        tar -xvf images.tgz
        cd $WORKINGDIR/images/
        for a in *.tar;do docker load -i $a;done
        cd $WORKINGDIR/
        rm -rf images.tgz
    fi
    cd /opt/fms/solution/deployment/
    if test -f ".env_used";then
        ./swarm.sh
    else
        ./swarm.sh --list-usefull-env >> .env_used
        sed -i '/^[  ]/d' .env_used
        sed -i '/^#/d' .env_used
        cp .env_used .env
        ./swarm.sh
    fi
fi
exit
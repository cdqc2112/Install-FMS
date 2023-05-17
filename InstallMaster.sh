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

echo "Script to install Docker and setup FMS on Ubuntu or CentOS"
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
# Single or multi node
echo "Storage volume"
echo "The storage can be a file system hosted on a local device, or network remote (NFS)."
echo "When using a storage on a local device, the backup functionality can be installed, if volumes are created over LVM."
echo
if [ -f "$WORKINGDIR/.singlenode" ];then
    echo "Single node"
elif [ -f "$WORKINGDIR/.multinode" ];then 
    echo "Multi node"
else
    read -r -p 'Is this a single node with local volume storage? [y/N] ' response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
            touch $WORKINGDIR/.singlenode
        else
            touch $WORKINGDIR/.multinode 
        fi
fi
# URL
if [ -f "$WORKINGDIR/.url" ];then
    DOMAIN=$(ls -tr|grep *.dom)
    DOMAIN="${DOMAIN::-4}"
    echo "URL $DOMAIN will be used"
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
    touch $WORKINGDIR/.url
    done
fi
# Certificate
if [ -f "$WORKINGDIR/.certs" ];then
    read -n 1 -r -s -p $'Certificates already created. Press enter to continue...\n'
else
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
                echo
                echo "The rootCA.crt will be created in /opt/fms/solution/cer. It has to be installed in browser"
                echo "or imported into Trusted Root Certification Authorities." 
                echo "It should also be installed on the RTUs"
                read -n 1 -r -s -p $'Press enter to continue...\n'
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
# Worker
if [ ! -f "$WORKINGDIR/.singlenode" ];then
    read -r -p 'Will there be worker nodes to set-up, including replica? [y/N] ' response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
        touch $WORKINGDIR/.worker
    fi
    read -r -p 'Will there be replica node to set-up? [y/N] ' response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
        touch $WORKINGDIR/.replica
    fi
fi
# GIS
read -r -p 'Are you using GIS addon? [y/N] ' response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
    touch $WORKINGDIR/.gis
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
# Offline
if [ -f "$WORKINGDIR/.offline" ];then
    cd $WORKINGDIR/packages
    if [ "$FMS_INSTALLER" = "apt" ]; then
        dpkg -i *.deb
    else
        rpm -iUvh *.rpm
    cd $WORKINGDIR
    fi
else
# Online
    $FMS_INSTALLER install -y \
            dos2unix \
            bash-completion \
            rsync \
            openssl \
            lvm2
fi
# Firewall
if [ -f "$WORKINGDIR/.firewall" ];then
    read -n 1 -r -s -p $'Firewall done. Press enter to continue...\n'
    if [ "$FMS_INSTALLER" = "apt" ]; then
        ufw allow 2377/tcp
        ufw allow 7946
        ufw allow 4789/udp
        ufw allow 443
        ufw allow 61617
        ufw allow 500/udp
        ufw allow 4500/udp
        ufw allow nfs
    else
        firewall-cmd --zone=public --permanent --add-port=2377/tcp
        firewall-cmd --zone=public --permanent --add-port=7946/tcp
        firewall-cmd --zone=public --permanent --add-port=7946/udp
        firewall-cmd --zone=public --permanent --add-port=4789/udp
        firewall-cmd --zone=public --permanent --add-port=443/tcp
        firewall-cmd --zone=public --permanent --add-port=61617/tcp
        firewall-cmd --zone=public --permanent --add-port=500/udp
        firewall-cmd --zone=public --permanent --add-port=4500/udp
        firewall-cmd --zone=public --permanent --add-service="ipsec"
        firewall-cmd --zone=public --permanent --add-service=nfs
        firewall-cmd --zone=public --permanent --add-service=rpc-bind
        firewall-cmd --zone=public --permanent --add-service=mountd
        firewall-cmd --reload
    fi
    touch $WORKINGDIR/.firewall
fi
# LVM for single node
if [ -f "$WORKINGDIR/.volume" ];then
    echo "Volume done"
else [ -f "$WORKINGDIR/.singlenode" ];then
    clear
    echo "This will create a single LVM to hold the FMS application files and backups"
    echo -e "A separated volume is required and will be erased"
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
    read -n 1 -r -s -p $'LVM setup done. Press enter to continue...\n'
else
    # Mount NFS
    Install NFS client
    $FMS_INSTALLER install -y nfs-common
    $FMS_INSTALLER install -y nfs-utils
    mkdir -p /opt/fms/solution
    echo "A NFS share is required to hold the FMS application files"
    read -p 'Enter the NFS share path (x.x.x.x:/share): ' SHARE
    echo $SHARE /opt/fms/solution nfs4 rsize=65536,wsize=65536,hard,timeo=600,retrans=2 0 0 | tee /etc/fstab -a
    mount -av
    mkdir -p /opt/fms/solution/cer
    touch $WORKINGDIR/.volume
    echo "$(date): NFS client installed" >> $LOGFILE
fi
# Install Docker
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
exit
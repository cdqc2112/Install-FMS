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
#Installation options
read -r -p 'Is this an offline installation? [y/N] ' response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
    touch $WORKINGDIR/.offline
fi
#Single or multi node
read -r -p 'Is this a single node with local volume storage? [y/N] ' response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
    touch $WORKINGDIR/.singlenode
fi
#URL
if [ -f "$WORKINGDIR/.url" ];then
    read -n 1 -r -s -p $'URL done. Press enter to continue...\n'
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
    touch $WORKINGDIR/.url
    done
fi
#Certificate
if [ -f "$WORKINGDIR/.certs" ];then
    read -n 1 -r -s -p $'Certificates already created. Press enter to continue...\n'
else
    read -r -p 'Do you have the certificate? [y/N] ' response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
            echo "Copy certificate ${DOMAIN}.crt and private key ${DOMAIN}.key to folder $WORKINGDIR"
            echo "CERT"
            touch $WORKINGDIR/.certs
    else
        read -r -p 'Do you want to generate a private key and a certificate request? [y/N] ' response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
            echo "CSR"
            touch $WORKINGDIR/.certs
        else
            read -r -p 'Do you want to generate a self-signed certificate? [y/N] ' response
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
                echo "SSC"
                touch $WORKINGDIR/.certs
            fi
        fi
    fi
fi
#Worker
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
#GIS
read -r -p 'Are you using GIS addon? [y/N] ' response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
    touch $WORKINGDIR/.gis
fi
#Offline Installation
if [ -f "$WORKINGDIR/.offline" ];then
    while true; do
        if [ ! -f "$WORKINGDIR/images.tgz" ];
        then
            echo
            read -n 1 -r -s -p $"Required images.tgz file is missing. Copy the file in $WORKINGDIR and press enter to continue...\n"
            echo
            continue
        fi
    break
done
fi
#Install packages
#offline
if [ -f "$WORKINGDIR/.offline" ];then
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
            openssl \
            lvm2
fi
#Firewall
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
#LVM for single node

#Mount NFS

#Install Docker

#Certificates

exit
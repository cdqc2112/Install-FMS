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

#LVM for single node

#Mount NFS

#Install Docker

#Certificates

exit
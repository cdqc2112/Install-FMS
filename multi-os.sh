#!/bin/bash

source /etc/os-release

if [ "$ID" = "ubuntu" ]; then
    FMS_UNIX_USER="ubuntu"
elif [ "$ID" = "centos" ]; then
    FMS_UNIX_USER="centos"     
else
    FMS_UNIX_USER="ec2-user"
fi

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
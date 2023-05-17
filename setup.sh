#!/bin/bash

BG_BLUE="$(tput setab 4)"
BG_BLACK="$(tput setab 0)"
FG_GREEN="$(tput setaf 2)"
FG_WHITE="$(tput setaf 7)"

# Save screen
tput smcup

# Display menu until selection == 0
while [[ $REPLY != 0 ]]; do
  echo -n ${BG_BLUE}${FG_WHITE}
  clear
  cat <<- _EOF_
    Script to install Docker and setup FMS on Ubuntu or CentOS

    Docker engine data

    Docker will require disk space on every nodes for the purpose of storing docker images, container logs and runtime temporary files.

    It is advised to allocate a specific partition for the /var/lib/docker directory, with at least 60Gb.
    If no specific partition is used, this 60Gb will be consummed on the root partition, so the root partition
    must be sized accordingly (increased by 60Gb from normal OS requirement).

    The usage intensity on this storage will not be related to the load applied to the server. A SSD class storage is recommanded.

    FMS data

    A dedicated disk volume is required for the FMS data, on the following two server nodes:

        The only node in single-server architecture, when not using NFS
        Replica nodes in Replication or Cross-site redundancy architectures

    The disk must be visible at the OS level as a block device (ex: /dev/sdb)

    The required capacity and bandwidth for the disk depends on the FMS usage, please refer to the sizing guide for actual values.

    The disk must not initially be partitionned, as the installation process includes a specific partitioning process using LVM.

    Please Select:

    1. Install FMS on Master node
    2. Setup Worker/Replica node
    3. Start FMS
    4. Test ports
    5. Test NFS share
    0. Quit

_EOF_

read -p "Enter selection [0-2] > " selection
      
# Clear area beneath menu
tput cup 10 0
echo -n ${BG_BLACK}${FG_GREEN}
tput ed
tput cup 11 0

# Act on selection
case $selection in
  1)  ./InstallMaster.sh
      ;;
  2)  ./InstallWorker.sh
      ;;
  3)  ./start-fms.sh
      ;;
  4)  ./testPorts.sh
      ;;
  5)  ./nfsCheck.sh
      ;;
  0)  break
      ;;
  *)  echo "Invalid entry."
      ;;
esac
printf "\n\nPress any key to continue."
read -n 1
done

# Restore screen
tput rmcup
#Display login for admin user
DOMAIN=$(ls -tr|grep *.dom)
DOMAIN="${DOMAIN::-4}"
docker service ls
PASS=$(awk '/KEYCLOAK_FIBER_ADMIN_USER_INIT_SECRET/{print $3}' /opt/fms/solution/deployment/secrets)
echo
echo "You will be able to login to https://${DOMAIN} with username: admin and password: ${PASS} when all services are started"
echo
echo "" >> install.log 
cat /etc/os-release >> install.log
echo "" >> install.log
docker info >> install.log
echo "" >> install.log
free -h >> install.log
exit
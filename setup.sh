#!/bin/bash
#set -euxo pipefail
BG_BLUE="$(tput setab 4)"
BG_BLACK="$(tput setab 0)"
FG_GREEN="$(tput setaf 2)"
FG_WHITE="$(tput setaf 7)"

# Save screen
tput smcup
REPLY=
# Display menu until selection == 0
while [[ $REPLY != 0 ]]; do
  echo -n ${BG_BLUE}${FG_WHITE}
  clear
  cat <<- _EOF_
    
    
    Script to install Docker and setup FMS 7.13.0.2 on Ubuntu or CentOS

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

    To add more workers, run option 1 again.

    Please Select:

    1. Install FMS on Master node
    2. Setup Worker/Replica node
    3. Start FMS
    4. Check services
    5. Test ports
    6. Test NFS share
    0. Quit

_EOF_

read -p "Enter selection [0-6] > " selection
      
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
  4)  docker service ls
      ;;
  5)  ./testPorts.sh
      ;;
  6)  ./nfsCheck.sh
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
if [ ! -f "info.txt" ];then
    touch info.txt
    echo "" >> info.txt
    cat /etc/os-release >> info.txt
    echo "" >> info.txt
    docker info >> info.txt
    echo "" >> info.txt
    free -h >> info.txt
fi
exit
#! /bin/bash
set -euo pipefail
WORKINGDIR=${PWD}
mount -t nfs
mount -t nfs4
echo
if [ -f "$WORKINGDIR/.replica" ];then
    nfsiostat /opt/fms/master 5
else
    nfsiostat /opt/fms/solution 5
fi
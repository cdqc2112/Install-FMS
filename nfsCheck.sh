#! /bin/bash
set -euo pipefail
mount -t nfs
mount -t nfs4
echo
nfsiostat /opt/fms/solution 5
# Install-FMS

Installation script for FMS 7.13.0.2, online and offline on Ubuntu 20.04, 22.04 or CentOS 7

For offline installation, copy images.tgz to installation folder

Included addons:

  email-fault-image-provider.addon,
  self-monitoring.addon,
  trending-supervision.addon,
  gis.addon

Missing offline packages can be downloaded from https://pkgs.org/

• Installation

Run setup.sh to install FMS on master node and/or setup worker/replica node

• Volumes and NFS share requirements

Single node (master with backups)

	- One volume for /boot, /swap and OS
	- Minimum disk space of 60GB for /var/lib/docker
	- A second volume for /opt/fms/solution and /opt/fms/replication

Single node (master without backups)

	- One volume for /boot, /swap and OS
	- Minimum disk space of 60GB for /var/lib/docker
	- NFS share mounted on /opt/fms/solution
	
Multi-node no replica (master and worker(s) without backups)

	- One volume for /boot, /swap and OS on master and worker nodes
	- Minimum disk space of 60GB for /var/lib/docker on master and worker nodes
	- An NFS share mounted on /opt/fms/solution for master and worker nodes

Multi-node with replica (master and worker(s) with backups and data replication)

	- One volume for /boot, /swap and OS on master and replica nodes
	- Minimum disk space of 60GB for /var/lib/docker on master, worker(s) and replica nodes
	- A second volume for backups on replica node
	- An NFS share mounted on /opt/fms/solution on master and worker(s) nodes, and mounted on /opt/fms/master for replica node

Multi-node with replica (dormant stack for disaster recovery option)

	- Same configuration as above
	- An NFS share for dormant stack only
	
• Setups

Single node with local data and backup volume

	- Main data volume setup. Change sdb for actual disk name

	parted /dev/sdb mklabel msdos
	parted -m -s /dev/sdb unit mib mkpart primary 1 100%
	pvcreate /dev/sdb1
	vgcreate replica_vg /dev/sdb1
	lvcreate -l 25%VG -n replica_live replica_vg
	lvcreate -l 50%VG -n replica_backups replica_vg
	mkfs.xfs /dev/replica_vg/replica_live
	mkfs.xfs /dev/replica_vg/replica_backups
	mkdir -p /opt/fms/solution
	mkdir -p /opt/fms/replication
	mkdir -p /opt/fms/replication/backup
	mkdir -p /mnt/snapshot

	- Add mount points to fstab

	vim /etc/fstab
	
	/dev/replica_vg/replica_live	/opt/fms/solution	xfs	defaults,nofail	0	0
	/dev/replica_vg/replica_backups	/opt/fms/replication/backup	xfs	defaults,nofail	0	0
	
	- Mounting

	mount -avt xfs
	
	- Check mapping

	lsblk
	
	Expected output
	
	NAME                           MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
	sda                              8:0    0   96G  0 disk 
	├─sda1                           8:1    0    1G  0 part /boot
	└─sda2                           8:2    0   95G  0 part 
	  ├─centos-root                253:0    0   50G  0 lvm  /
	  ├─centos-swap                253:1    0  7.9G  0 lvm  [SWAP]
	  └─centos-home                253:2    0 37.1G  0 lvm  /home
	sdb                              8:16   0   96G  0 disk 
	└─sdb1                           8:17   0   96G  0 part 
	  ├─replica_vg-replica_live    253:3    0   24G  0 lvm  /opt/fms/solution
	  └─replica_vg-replica_backups 253:4    0   48G  0 lvm  /opt/fms/replication/backup
	sr0                             11:0    1  973M  0 rom

	- Create required symbolic link

	sudo ln -s /opt/fms/solution /opt/fms/master ##no replica

	- Create required folders

	mkdir -p /opt/fms/replication/backup/history
	mkdir -p /opt/fms/solution/deployment
	mkdir -p /opt/fms/solution/cer
	
For some architecture, an NFS share is required. It must meet the following requirements:

	- Low latency to the primary. It must be setup close to the FMS stack for good performance.
	- The recommended option combination is:
		- nosuid on the NFS server volume
		- no_root_squash on the NFS server export
		- nosuid on the NFS clients

Single node with NFS share (no backups)

	- Install NFS client

	yum install -y nfs-common nfs-utils **CentOS
	apt install -y nfs-common nfs-utils **Ubuntu

	- Create solution folder

	mkdir -p /opt/fms/solution

	- Add mount point in fstab

	vim /etc/fstab
	
	<nfsServer:/share> /opt/fms/solution  nfs4 rsize=65536,wsize=65536,hard,timeo=600,retrans=2 0 0

	- Mount NFS share

	mount -at xfs
	
	- Create required folders

	mkdir -p /opt/fms/solution/deployment
	mkdir -p /opt/fms/solution/cer 

Multi node with no replica

	- Execute the steps of Single node with NFS share (no backups) section on master

	- Execute only the 4 first steps of Single node with NFS share (no backups) section on worker(s)

Multi node with replica

	- Execute the steps of Single node with NFS share (no backups) section on master
	
	- Execute only the 4 first steps of Single node with NFS share (no backups) section on worker(s)
	
	- Execute only the first step of Single node with NFS share (no backups) section on replica
	
	- Create master folder on replica

	mkdir -p /opt/fms/master

	- Add mount point in fstab on replica

	vim /etc/fstab
	
	<nfsServer:/share> /opt/fms/master nfs4 rsize=65536,wsize=65536,hard,timeo=600,retrans=2 0 0

	- Mount NFS share on replica

	mount -at xfs
	
	- Setup volume for replication data and backups on replica

	/opt/fms/master/deployment/backup/./setup.sh
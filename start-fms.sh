#! /bin/bash
# Starting FMS
WORKINGDIR=${PWD}
if [ -f "$WORKINGDIR/.secrets" ];then
    echo "Secrets already done."
else
    touch $WORKINGDIR/.secrets
    cd /opt/fms/solution/deployment/
    ./swarm.sh --init-iam-users --fill-secrets --no-deploy >> secrets
    if [ -f "$WORKINGDIR/global.json" ];then
        mv $WORKINGDIR/global.json /opt/fms/solution/config/topology_ui
    fi
    chmod -R 755 /opt/fms/solution/config/
    chown -R root /opt/fms/solution/config
    chmod -R ugo+rX,go-w /opt/fms/solution/config
fi
read -r -p 'Are you ready to start the FMS? [y/N] ' response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]];then
    if [ -f "$WORKINGDIR/.offline" ];then
        cd $WORKINGDIR/
        tar -xvf images.tgz
        cd $WORKINGDIR/images/
        for a in *.tar;do docker load -i $a;done
        cd $WORKINGDIR/
        rm -rf images.tgz
    fi
    cd /opt/fms/solution/deployment/
    if [ -f ".env_used" ];then
        ./swarm.sh
    else
        ./swarm.sh --list-usefull-env >> .env_used
        sed -i '/^[  ]/d' .env_used
        sed -i '/^#/d' .env_used
        cp .env_used .env
        ./swarm.sh
    fi
fi
#Backup
if [ -f "$WORKINGDIR/.singlenode" ];then
    printf '#!/bin/bash\ncd /opt/fms/solution/deployment/backup && exec ./backup.sh > /dev/null 2>&1\n' > /etc/cron.daily/fms_backup
    chmod +x /etc/cron.daily/fms_backup
fi
#Display login for admin user
cd $WORKINGDIR
DOMAIN=$(ls -tr|grep *.dom)
DOMAIN="${DOMAIN::-4}"
PASS=$(awk '/KEYCLOAK_FIBER_ADMIN_USER_INIT_SECRET/{print $3}' /opt/fms/solution/deployment/secrets)
echo
echo "You will be able to login to https://${DOMAIN} with username: admin and password: ${PASS} when all services are started"
echo ""
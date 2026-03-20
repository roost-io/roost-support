#!/bin/bash

ROOST_DIR="/var/tmp/Roost"
ROOST_LOG="${ROOST_DIR}/logs"
ROOST_BIN="${ROOST_DIR}/bin"

set -x
exec 2>&1 >> ${ROOST_LOG}/launcher.log
echo
echo "===="
echo
date


SUDO=sudo
if [ -z "${APPNAME}" ];then
  echo "APPNAME was not provided"
  exit
fi

debug=false
if [ -f "${ROOST_DIR}/.dev" ]; then
  debug=true
  DEV=1
fi
if [ -z "$DEV" ]; then
  debug=false
  DEV=0
fi
if [ $DEV -eq 1 ]; then
    debug=true
fi

if [ -z "${ENTSERVER}" ];then
  ENTSERVER=$(curl -s ifconfig.me)
else
  ENTSERVER=${ENTSERVER:-roost.io:443}
fi

CIDRBLOCK=${CIDRBLOCK:-'0.0.0.0/0'}
ROOSTREGION=${ROOSTREGION:-'us-west-1'}
ROOSTVPC=${ROOSTVPC:-''}

add_fstab() {
  echo "Check etc fstab entry"
  uuid=$(lsblk -f -d -p -n -o NAME,UUID,MOUNTPOINT | grep "$ROOST_DIR" | awk '{print $2}')
  if [ $? -ne 0 ]; then
	  return
  fi
  line="UUID=${uuid}\t${ROOST_DIR}\text4\tdefaults\t0\t2"
  grep $ROOST_DIR /etc/fstab
  if [ $? -ne 0 ];then
    echo $line | sudo tee -a /etc/fstab
  fi
}

install_prereqs() {
  if [ ! -d "${ROOST_BIN}" ]; then
    sudo mkdir -p ${ROOST_BIN}
  fi
  # all sub-folders under ROOST_DIR
  sudo chown -R ${USER}:`id -g` ${ROOST_DIR}

  add_fstab
  write_initd_script
  write_restart_script
}

remove_existing_process() {
  sudo pgrep 'ec2Launcher|ec2launcher' | grep -v $$ | xargs -r sudo kill -9

  # ps -aef | grep -w ec2Launcher | grep -v $$ | grep -v grep | awk '{print $2}' | xargs -r sudo kill -9
  # ps -aef | grep -w ec2launcher | grep -v $$ | grep -v grep | awk '{print $2}' | xargs -r sudo kill -9
  sleep 10
}

write_restart_script() {
cat <<EOF > $ROOST_BIN/restartScript.sh
#!/bin/bash
set -x
echo
echo "===="
echo
date
ps cax | grep ec2launcher
if [ \$? -eq 0 ]; then
  echo "EC2Launcher Process is running."
else
  verbose=3
  if $debug; then
    verbose=4
  fi
  echo "EC2Launcher Process is not running."
  if [ -z "${ENTSERVER}" ];then
    $ROOST_BIN/ec2launcher -appName=$APPNAME -verbose=\$verbose &
  else
    $ROOST_BIN/ec2launcher -appName=$APPNAME -entServer=$ENTSERVER -roostVersion=$ROOST_VER -verbose=\$verbose &
  fi
  ps cax | grep ec2launcher
  if [ \$? -eq 0 ]; then
    echo "EC2Launcher Process is now running ok."
  else
    echo "EC2Launcher Process is STILL NOT running."
  fi
fi

ps cax | grep releaseServer
if [ \$? -eq 0 ]; then
  echo "ReleaseServer Process is running."
else
  verbose=3
  if $debug; then 
    verbose=4
  fi
  echo "ReleaseServer Process is not running."
  if [ -z "${ENTSERVER}" ];then
    $ROOST_BIN/releaseServer -verbose=\$verbose -port=60003 &
  else
    $ROOST_BIN/releaseServer -verbose=\$verbose -entServer=$ENTSERVER -port=60003 -roostVersion=$ROOST_VER &
  fi
  ps cax | grep releaseServer
  if [ \$? -eq 0 ]; then
    echo "ReleaseServer Process is now running ok."
  else
    echo "ReleaseServer Process is STILL NOT running."
  fi
fi

ps cax | grep aiServer
if [ \$? -eq 0 ]; then
  echo "aiServer Process is running."
else
  verbose=3
  if $debug; then
    verbose=4
  fi
  echo "aiServer Process is not running."
  if [ -z "${ENTSERVER}" ];then
    $ROOST_BIN/aiServer -verbose=\$verbose -port=60007 -roostVersion=$ROOST_VER &
  else
    $ROOST_BIN/aiServer -verbose=\$verbose -entServer=$ENTSERVER -port=60007 -roostVersion=$ROOST_VER &
  fi
  ps cax | grep aiServer
  if [ \$? -eq 0 ]; then
    echo "aiServer Process is now running ok."
  else
    echo "aiServer Process is STILL NOT running."
  fi
fi

LOG="${ROOST_LOG}/restart.log"
N=200
last=\$(wc -l ${LOG} | awk '{print \$1}')
lastN=\$((last-N))
if [ \$lastN -gt \$N ];then
  sed -i "\${lastN},\${last}! d" "${LOG}"
fi
EOF

chmod +x $ROOST_BIN/restartScript.sh
verbose=3
if $debug; then 
  verbose=4
fi
# adding cron jobs
# (crontab -l; echo "30 0 * * * ${ROOST_BIN}/cloudCleanUp -entServer=$ENTSERVER -verbose=$verbose -command=all -logfile=${ROOST_LOG}/cloudCleanUp.log -configFile=$ROOST_BIN/cloudCleanUp.json") | awk '!x[$0]++' | crontab -
(crontab -l; echo "*/5 * * * * ${ROOST_BIN}/restartScript.sh >> ${ROOST_LOG}/restart.log") | awk '!x[$0]++' | crontab -

# Remove Crontab entries from root if existing
CRON_PATTERN="cloudCleanUp|restartScript"
sudo crontab -l | egrep -v ${CRON_PATTERN} | sudo crontab -
}

write_initd_script() {
cat <<EOF > ${ROOST_DIR}/roost-ec2Launcher
#!/bin/sh
set -e
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
Ec2LauncherScript=${ROOST_BIN}/ec2Launcher.sh
Ec2LaunchBin=${ROOST_BIN}/ec2launcher
ReleaseSvrBin=${ROOST_BIN}/releaseServer
AiSvrBin=${ROOST_BIN}/aiServer

# Get lsb functions
. /lib/lsb/init-functions

start_process() {
  export APPNAME=$APPNAME ENTSERVER=$ENTSERVER ROOST_VER=$ROOST_VER CIDRBLOCK=$CIDRBLOCK ROOSTREGION=$ROOSTREGION ROOSTVPC=$ROOSTVPC
  ${ROOST_BIN}/ec2Launcher.sh
  log_end_msg \$?
  if [ $ENTSERVER = "http://127.0.0.1:3000" ]; then
    echo "Starting in Single Host mode, call script again since the enterprise_dns will need a change"
    ROOST_VER=$ROOST_VER $ROOST_BIN/roost-enterprise.sh -c $ROOST_DIR/config.json -i ec2
  fi
}
stop_process() {
  sudo pkill "${Ec2LaunchBin}|${ReleaseSvrBin}|${AiSvrBin}"
  running_procs=\$(ps -aef |egrep "\$Ec2LaunchBin|\$ReleaseSvrBin|\$AiSvrBin" | egrep -v "grep" | awk '{print \$2}' | xargs)
  for pid in \$running_procs; do
    sudo kill -9 \$pid
  done
}
case "\$1" in
  start)
    start_process
    ;;
  stop)
    stop_process
    ;;
  restart)
    stop_process
    start_process
    ;;
  status)
  # pgrep "${Ec2LaunchBin}|${ReleaseSvrBin}|${AiSvrBin}" | tee -a /var/tmp/Roost/status.txt
	running_procs=\$(ps -aef |egrep "\$Ec2LaunchBin|\$ReleaseSvrBin|\$AiSvrBin" | egrep -v "grep" | awk '{print \$2}' | xargs)
	echo "\$running_procs" | tee -a /var/tmp/Roost/status.txt
    ;;
  *)
    echo "Usage: service roost {start|stop|restart|status}"
    exit 1
    ;;
esac
EOF

  if [ -s "/etc/init.d/roost-ec2Launcher" ]; then
    diff -q ${ROOST_DIR}/roost-ec2Launcher "/etc/init.d/roost-ec2Launcher"
    diffStat=$?
  else
    diffStat=1
  fi
  if [ $diffStat -ne 0 ];then
    sudo cp ${ROOST_DIR}/roost-ec2Launcher /etc/init.d/roost-ec2Launcher
    sudo chmod 755 /etc/init.d/roost-ec2Launcher
  fi

  if [ ! -L "/etc/rc4.d/S01roost-ec2Launcher" ]; then
    cd /etc/rc4.d
    sudo ln -s ../init.d/roost-ec2Launcher S01roost-ec2Launcher
  fi
}

add-fstab() {
    uuid=$(lsblk -f -d -p -n -o NAME,UUID,MOUNTPOINT | grep "$ROOST_DIR" | awk '{print $2}')
    line="UUID=${uuid}\t${ROOST_DIR}\text4\tdefaults\t0\t2"
    grep $ROOST_DIR /etc/fstab
    if [ $? -ne 0 ];then
	    echo $line | sudo tee -a /etc/fstab
    fi
}

check_disk_space() {
    df -h / | awk 'int($5)>60{print "Partition "$1" has only "$4" free"}'
    df -h $ROOST_DIR | awk 'int($5)>60{print "Partition "$1" has only "$4" free"}'
}

start_ec2launcher() {
  
  remove_existing_process
  check_disk_space

  echo "start ec2launcher"
  verbose=3
  if $debug; then
    verbose=4
  fi
  #Launch the ec2 launcher
  if [ -z "${ENTSERVER}" ];then
    $ROOST_BIN/ec2launcher -appName=$APPNAME -verbose=$verbose &
  else
    $ROOST_BIN/ec2launcher -appName=$APPNAME -entServer=$ENTSERVER -roostVersion=$ROOST_VER -cidrBlock=$CIDRBLOCK -roostRegion=$ROOSTREGION -roostVPC=$ROOSTVPC -verbose=$verbose &
  fi
}

start_release_server() {
  echo "start releaseServer.sh"
  $ROOST_BIN/releaseServer.sh &
}

start_ai_server() {
  echo "start aiServer.sh"
  $ROOST_BIN/aiServer.sh &
}

main() {
  install_prereqs
  if [ $ENTSERVER = "http://127.0.0.1:3000" ]; then
    echo "Do not start processes from container, rather let crontab start it in a while"
  fi
  grep_status=1
  commitid=$(curl -s http://127.0.0.1:60003/api/status | jq -r .gitCommit)
  if [ ! -z "$commitid" ]; then
    grep $commitid $ROOST_BIN/releaseServer.commitid
    grep_status=$?
  fi
  if [ $grep_status -ne 0 ]; then
    start_ec2launcher
    start_release_server
  fi
  grep_status=1
  ai_commitid=$(curl -s http://127.0.0.1:60007/api/status | jq -r .gitCommit)
  if [ ! -z "$ai_commitid" ]; then
    grep $ai_commitid $ROOST_BIN/aiServer.commitid
    grep_status=$?
  fi
  if [ $grep_status -ne 0 ]; then
    start_ai_server
  fi
}

main
echo "Done: $(date)"


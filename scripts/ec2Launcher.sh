#!/bin/bash

ROOST_DIR="/var/tmp/Roost"
ROOST_LOG="${ROOST_DIR}/logs"
ROOST_BIN="${ROOST_DIR}/bin"
ROOST_UID=10001
ROOST_GID=10001

# umask 0022: new files created as 644, dirs as 755 — allows roost user to read/execute
umask 0022

sudo mkdir -p "${ROOST_LOG}" 2>/dev/null || true
# Setup logging with proper permissions
{
  echo
  echo "==== EC2 Launcher Setup ===="
  echo "Started: $(date)"
  echo
} | sudo tee -a "${ROOST_LOG}/launcher.log" > /dev/null


echo "Validating environment..."
if [ -z "${APPNAME}" ]; then
  echo "APPNAME was not provided"
  exit
fi

debug=false
DEV=${DEV:-0}
if [ -f "${ROOST_DIR}/.dev" ] || [ "$DEV" = "1" ]; then
  debug=true
  set -x
  echo "DEBUG MODE ENABLED"
fi

ENTSERVER=${ENTSERVER:-$(curl -s ifconfig.me 2>/dev/null || echo "")}
ENTSERVER=${ENTSERVER:-roost.io:443}
CIDRBLOCK=${CIDRBLOCK:-'0.0.0.0/0'}
ROOSTREGION=${ROOSTREGION:-'us-west-1'}
ROOSTVPC=${ROOSTVPC:-''}

echo "Configuration:"
echo "  APPNAME: ${APPNAME}"
echo "  ENTSERVER: ${ENTSERVER}"
echo "  ROOST_DIR: ${ROOST_DIR}"
echo "  DEBUG: ${debug}"


add_fstab() {
  echo "Checking fstab entry..."
  
  # Try to find UUID
  local uuid=$(lsblk -f -d -p -n -o NAME,UUID,MOUNTPOINT 2>/dev/null | grep "$ROOST_DIR" | awk '{print $2}' || echo "")
  
  if [ -z "$uuid" ]; then
    echo "ⓘ Could not find UUID for $ROOST_DIR mount point (may not be mounted yet)"
    return 0
  fi
  
  local line="UUID=${uuid}\t${ROOST_DIR}\text4\tdefaults\t0\t2"
  
  if ! grep -q "$ROOST_DIR" /etc/fstab 2>/dev/null; then
    echo "$line" | sudo tee -a /etc/fstab > /dev/null
    echo "✓ Added fstab entry for $ROOST_DIR"
  else
    echo "✓ fstab entry already exists"
  fi
}

add_roost_user() {
  echo "Setting up roost user..."
  
  # Validate existing user UID
  local EXISTING_UID=$(id -u roost 2>/dev/null || echo "")
  if [ -n "$EXISTING_UID" ] && [ "$EXISTING_UID" != "$ROOST_UID" ]; then
    echo "ERROR: roost user exists with UID $EXISTING_UID, expected $ROOST_UID"
    exit 1
  fi
  
  # Ensure group exists with correct GID
  if ! getent group roost >/dev/null 2>&1; then
    if ! sudo groupadd -g ${ROOST_GID} roost 2>/dev/null; then
      echo "ERROR: Failed to create roost group"
      exit 1
    fi
    echo "✓ Created roost group (GID: ${ROOST_GID})"
  fi
  
  # Ensure user exists with correct UID
  if ! id -u roost >/dev/null 2>&1; then
    if ! sudo useradd -u ${ROOST_UID} -g ${ROOST_GID} -M -r \
      -s /usr/sbin/nologin roost 2>/dev/null; then
      echo "ERROR: Failed to create roost user"
      exit 1
    fi
    echo "✓ Created roost user (UID: ${ROOST_UID})"
  fi
  
  # Add roost to docker group if docker is installed
  if getent group docker >/dev/null 2>&1; then
    sudo usermod -aG docker roost 2>/dev/null || true
    echo "✓ Added roost to docker group"
  fi
}

install_prereqs() {

  sudo mkdir -p ${ROOST_BIN} ${ROOST_LOG}
  if [ "$(stat -c %u ${ROOST_DIR})" != "${ROOST_UID}" ]; then
    sudo chown -R ${ROOST_UID}:${ROOST_UID} ${ROOST_DIR} || true
  fi

  echo "Applying permissions for UID ${ROOST_UID}"
  # all sub-folders under ROOST_DIR
  if [ "$(stat -c %u ${ROOST_DIR})" != "${ROOST_UID}" ]; then
    sudo chown -R ${ROOST_UID}:${ROOST_UID} ${ROOST_DIR} || true
  fi
  sudo chmod -R 775 "${ROOST_DIR}"
  sudo find "${ROOST_DIR}" -type d -exec chmod g+s {} \;
  # Allow traversal for non-roost users (ubuntu SSH execution) without world-write on top dirs
  sudo chmod 2771 "${ROOST_DIR}"
  sudo chmod 2771 "${ROOST_BIN}"

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
cat <<EOF | sudo tee $ROOST_BIN/restartScript.sh > /dev/null
#!/bin/bash
set -x
echo
echo "===="
echo
date

ps cax | grep aiServer
if [ \$? -eq 0 ]; then
  echo "aiServer Process is running."
  exit
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

sudo chmod 755 $ROOST_BIN/restartScript.sh
# Transfer ownership to roost user so the crontab (runs as roost) can execute it
sudo chown ${ROOST_UID}:${ROOST_GID} $ROOST_BIN/restartScript.sh
verbose=3
if $debug; then
  verbose=4
fi
# adding cron jobs
# (crontab -l; echo "30 0 * * * ${ROOST_BIN}/cloudCleanUp -entServer=$ENTSERVER -verbose=$verbose -command=all -logfile=${ROOST_LOG}/cloudCleanUp.log -configFile=$ROOST_BIN/cloudCleanUp.json") | awk '!x[$0]++' | crontab -
(sudo -u roost crontab -l 2>/dev/null; echo "*/5 * * * * ${ROOST_BIN}/restartScript.sh >> ${ROOST_LOG}/restart.log") | awk '!x[$0]++' | sudo -u roost crontab -

# Remove Crontab entries from root if existing
CRON_PATTERN="cloudCleanUp|restartScript"
sudo crontab -l | egrep -v ${CRON_PATTERN} | sudo crontab -
}

write_initd_script() {
cat <<EOF | sudo tee ${ROOST_DIR}/roost-ec2Launcher > /dev/null
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
    sudo -u roost $ROOST_BIN/ec2launcher -appName=$APPNAME -verbose=$verbose &
  else
    sudo -u roost $ROOST_BIN/ec2launcher -appName=$APPNAME -entServer=$ENTSERVER -roostVersion=$ROOST_VER -cidrBlock=$CIDRBLOCK -roostRegion=$ROOSTREGION -roostVPC=$ROOSTVPC -verbose=$verbose &
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
  add_roost_user
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


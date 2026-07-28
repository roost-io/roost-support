#!/bin/bash
ROOST_DIR="/var/tmp/Roost"
ROOST_LOG="${ROOST_DIR}/logs"
ROOST_BIN="${ROOST_DIR}/bin"
ROOST_UID=10001
ROOST_GID=10001

# umask 0022: new files created as 644, dirs as 755 — consistent with other roost scripts
umask 0022

# Ensure logs dir exists and is owned by roost before redirecting output
if [ ! -d "${ROOST_LOG}" ]; then
  sudo mkdir -p "${ROOST_LOG}"
fi
sudo chown ${ROOST_UID}:${ROOST_GID} "${ROOST_LOG}" 2>/dev/null || true
sudo chmod 2775 "${ROOST_LOG}" 2>/dev/null || true
# Ensure the log file itself is appendable by the invoking user — it may be a
# pre-existing roost-owned 660 file that azureuser/ubuntu cannot write to.
sudo touch "${ROOST_LOG}/aiSvr.log" 2>/dev/null || true
sudo chown ${ROOST_UID}:${ROOST_GID} "${ROOST_LOG}/aiSvr.log" 2>/dev/null || true
sudo chmod 664 "${ROOST_LOG}/aiSvr.log" 2>/dev/null || true

# set -x
exec 2>&1 >> ${ROOST_LOG}/aiSvr.log
echo
echo "===="
echo
date

SUDO="sudo -u roost"

debug=false
if [ -f "${ROOST_DIR}/.dev" ]; then
    debug=true
    set -x
    echo "DEBUG MODE ENABLED"
fi

if [ -z "$DEV" ]; then
  debug=false
  DEV=0
fi

if [ $DEV -eq 1 ]; then
    debug=true
    set -x
    echo "DEBUG MODE ENABLED"
fi

ENTSERVER=${ENTSERVER:-$(curl -s ifconfig.me 2>/dev/null || echo "")}
ENTSERVER=${ENTSERVER:-roost.io:443}
CIDRBLOCK=${CIDRBLOCK:-'0.0.0.0/0'}
ROOSTREGION=${ROOSTREGION:-'us-west-1'}
ROOSTVPC=${ROOSTVPC:-''}
export ENTSERVER ROOST_VER CIDRBLOCK ROOSTREGION ROOSTVPC

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
  sudo find "${ROOST_DIR}" -type d -exec chmod g+s {} +
  # Allow traversal for non-roost users (ubuntu SSH execution) without world-write on top dirs
  sudo chmod 2771 "${ROOST_DIR}"
  sudo chmod 2771 "${ROOST_BIN}"

  add_fstab
  write_initd_script
  write_restart_script
}

remove_existing_process() {
  sudo pgrep 'aiServer.sh|aiServer' | grep -v $$ | xargs -r sudo kill -9
  # ps -aef | grep -w aiServer.sh |  grep -v $$ | grep -v grep | awk '{print $2}' | xargs -r sudo kill -9
  # ps -aef | grep -w aiServer |  grep -v $$ | grep -v grep | awk '{print $2}' | xargs -r sudo kill -9
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

check_disk_space() {
    df -h / | awk 'int($5)>60{print "Partition "$1" has only "$4" free"}'
    df -h $ROOST_DIR | awk 'int($5)>60{print "Partition "$1" has only "$4" free"}'
}
start_ai_server() {
  # Ensure binary is owned by roost and executable — guards against root-owned drop from copy_archive
  if [ -f "${ROOST_BIN}/aiServer" ]; then
    sudo chown ${ROOST_UID}:${ROOST_GID} "${ROOST_BIN}/aiServer" 2>/dev/null || true
    sudo chmod 755 "${ROOST_BIN}/aiServer" 2>/dev/null || true
  fi

  if [ ! -x ${ROOST_BIN}/aiServer ]; then
    echo "Did not find ${ROOST_BIN}/aiServer, so quit"
    return 1
  fi
  verbose=3
  debug=false
  [ -f "/var/tmp/Roost/.dev" ] && debug=true

  if $debug; then
    verbose=4
  fi
  
  if [ -z "${ENTSERVER}" ]; then
    $SUDO ${ROOST_BIN}/aiServer -verbose=$verbose &
  else
    $SUDO ${ROOST_BIN}/aiServer -verbose=$verbose -entServer=$ENTSERVER -port=60007 -roostVersion=$ROOST_VER &
  fi
}

# Returns 0 if aiServer is already running AND on the currently deployed commit.
# Used to skip an unnecessary kill+restart cycle when this script is invoked
# (e.g. by the backend launching a different app id) without any binary change.
aiserver_is_current() {
  local commitid deployed
  commitid=$(curl -s --max-time 3 http://127.0.0.1:60007/api/status 2>/dev/null \
             | grep -o '"gitCommit":"[^"]*"' | cut -d'"' -f4)
  [ -n "$commitid" ] || return 1
  # Exact match against the deployed commit id (whitespace trimmed) — a
  # substring match could wrongly treat a stale server as current.
  deployed=$(tr -d '[:space:]' < "${ROOST_BIN}/aiServer.commitid" 2>/dev/null)
  [ -n "$deployed" ] && [ "$commitid" = "$deployed" ]
}

main() {
  install_prereqs
  if aiserver_is_current && [ "${FORCE_RESTART:-0}" != "1" ]; then
    echo "aiServer already running on the deployed commit — skipping restart"
    echo "Done with ai server setup: $(date)"
    return 0
  fi
  remove_existing_process
  start_ai_server
  echo "Done with ai server setup: $(date)"
}

main

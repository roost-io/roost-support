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
sudo chmod 2770 "${ROOST_LOG}" 2>/dev/null || true

set -x
exec 2>&1 >> ${ROOST_LOG}/aiSvr.log
echo
echo "===="
echo
date

SUDO=""

debug=false
if [ -f "${ROOST_DIR}/.dev" ]; then
    debug=true
fi

if [ -z "$DEV" ]; then
  debug=false
  DEV=0
fi

if [ $DEV -eq 1 ]; then
    debug=true
fi

remove_existing_process() {
  sudo pgrep 'aiServer.sh|aiServer' | grep -v $$ | xargs -r sudo kill -9
  # ps -aef | grep -w aiServer.sh |  grep -v $$ | grep -v grep | awk '{print $2}' | xargs -r sudo kill -9
  # ps -aef | grep -w aiServer |  grep -v $$ | grep -v grep | awk '{print $2}' | xargs -r sudo kill -9
  sleep 10
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
  if $debug; then
    verbose=4
  fi
  if [ -z "${ENTSERVER}" ]; then
    $SUDO ${ROOST_BIN}/aiServer -verbose=$verbose &
  else
    $SUDO ${ROOST_BIN}/aiServer -verbose=$verbose -entServer=$ENTSERVER -port=60007 -roostVersion=$ROOST_VER &
  fi
}

main() {
  # install_prereqs
  remove_existing_process
  start_ai_server
  echo "Done with ai server setup: $(date)"
}

main

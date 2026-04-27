#!/bin/bash
ROOST_DIR="/var/tmp/Roost"
ROOST_LOG=$ROOST_DIR/"logs"

set -x
exec 2>&1 >> $ROOST_LOG/releaseSvr.log
echo
echo "===="
echo
date
ROOST_BIN="${ROOST_DIR}/bin"
SUDO="sudo -u roost"

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
  pgrep 'releaseServer.sh|releaseServer' | grep -v $$ | xargs -r sudo kill -9
  # ps -aef | grep -w releaseServer.sh |  grep -v $$ | grep -v grep | awk '{print $2}' | xargs -r sudo kill -9
  # ps -aef | grep -w releaseServer |  grep -v $$ | grep -v grep | awk '{print $2}' | xargs -r sudo kill -9
  sleep 10
}

start_release_server() {
  #Launch the releaseServer launcher
  if [ ! -x $ROOST_BIN/releaseServer ];then
    echo "Did not find $ROOST_BIN/releaseServer, so quit"
  fi
  verbose=3
  if $debug; then 
    verbose=4
  fi
  if [ -z "${ENTSERVER}" ];then
    $SUDO $ROOST_BIN/releaseServer -verbose=$verbose &
  else
    $SUDO $ROOST_BIN/releaseServer -verbose=$verbose -entServer=$ENTSERVER -port=60003 -roostVersion=$ROOST_VER -cidrBlock=$CIDRBLOCK -roostRegion=$ROOSTREGION -roostVPC=$ROOSTVPC &
  fi
}

main() {
  # install_prereqs
  remove_existing_process
  start_release_server
  echo "Done with Release server setup: $(date)"
}

main

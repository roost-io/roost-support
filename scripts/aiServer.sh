#!/bin/bash
ROOST_DIR="/var/tmp/Roost"
ROOST_LOG=$ROOST_DIR/"logs"

set -x
exec 2>&1 >> $ROOST_LOG/aiSvr.log
echo
echo "===="
echo
date

ROOST_BIN="${ROOST_DIR}/bin"
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
  #Launch the aiServer launcher
  if [ ! -x $ROOST_BIN/aiServer ];then
    echo "Did not find $ROOST_BIN/aiServer, so quit"
  fi
  verbose=3
  if $debug; then 
    verbose=4
  fi
  if [ -z "${ENTSERVER}" ];then
    $SUDO $ROOST_BIN/aiServer -verbose=$verbose &
  else
    $SUDO $ROOST_BIN/aiServer -verbose=$verbose -entServer=$ENTSERVER -port=60007 -roostVersion=$ROOST_VER &
  fi
}

main() {
  # install_prereqs
  remove_existing_process
  start_ai_server
  echo "Done with ai server setup: $(date)"
}

main

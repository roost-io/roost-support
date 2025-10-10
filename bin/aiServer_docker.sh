#!/bin/bash
ROOST_DIR="/var/tmp/Roost"
ROOST_BIN="$ROOST_DIR/bin"
if [ ! -d "$ROOST_DIR" ]; then
  echo "$ROOST_DIR does not exit, creating."
  mkdir -p ${ROOST_DIR}
fi
if [ ! -d "$ROOST_BIN" ]; then
  mkdir -p ${ROOST_BIN}
fi
cp -pf roost-bin/* ${ROOST_BIN}
# port and container_mode is defaulted
${ROOST_BIN}/aiServer --entServer=${ENT_SERVER} --verbose=${VERBOSE_LEVEL} --roostVersion=${ROOST_VER} --port=60007 --stdout=true

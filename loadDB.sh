#!/bin/sh
echo "set read only = ${NEOREADONLY} then launch neo4j service"
sed -i s/read_only=.*/read_only=${NEOREADONLY}/ ${NEOSERCONF} && \

echo 'Allow new plugin to make changes..'
echo 'dbms.security.procedures.unrestricted=apoc.*,gds.*' >> ${NEOSERCONF}

if [ -n "${BACKUPFILE}" ]; then
  if [ ! -d /data/databases/neo4j ]; then
    echo 'Resore KB from archive backup'
    cd /opt/VFB/backup/
    rm /opt/VFB/backup/${BACKUPFILE}.tar.gz
    wget http://data.virtualflybrain.org/archive/${BACKUPFILE}.tar.gz
    if [ ! -e ${BACKUPFILE}.tar.gz ]; then exit 1; fi
    tar -xzvf ${BACKUPFILE}.tar.gz
    mkdir -p /var/lib/neo4j/data/databases/
    neo4j-admin restore --from /opt/VFB/backup/neo4j --force
    rm -rf /opt/VFB/backup/*
    cd -
  fi
fi

echo -e '\nSTARTING VFB DB SERVER\n' >> /var/lib/neo4j/logs/query.log

#Output the query log to docker log:
tail -f /var/lib/neo4j/logs/query.log >/proc/1/fd/1 &

#TODO check for "Error upgrading database."

##########################################################################
# Crash-on-IOException watchdog
#   CRASH_PATTERN   : log substring to match      (default java.io.IOException)
#   CRASH_THRESHOLD : matches needed to stop       (default 1 = first match)
#   CRASH_WINDOW    : rolling window in seconds     (default 60)
#
# WARNING: CRASH_THRESHOLD=1 stops the container on the FIRST match. On a
# public endpoint 'Connection reset by peer' IOExceptions occur once per
# client/proxy disconnect, so 1 will restart the container on routine
# traffic. Raise CRASH_THRESHOLD (with CRASH_WINDOW) via the Rancher stack
# to fire only on a flood. read_only=true makes the hard kill safe.
##########################################################################
CRASH_PATTERN="${CRASH_PATTERN:-java.io.IOException}"
CRASH_THRESHOLD="${CRASH_THRESHOLD:-1}"
CRASH_WINDOW="${CRASH_WINDOW:-60}"

FIFO=/tmp/neo4j.out
rm -f "$FIFO"
mkfifo "$FIFO"

# Launch neo4j with stdout+stderr on the FIFO so the supervisor (this
# script, PID 1) can scan it and forward signals.
/docker-entrypoint.sh neo4j > "$FIFO" 2>&1 &
NEO4J_PID=$!

# Forward orchestrator shutdown to neo4j for a clean stop.
trap 'kill -TERM "$NEO4J_PID" 2>/dev/null' TERM INT

# Scanner: forward every line to the container log, count CRASH_PATTERN
# within CRASH_WINDOW, stop the container on threshold.
(
  hits=""
  while IFS= read -r line; do
    printf '%s\n' "$line"
    case "$line" in
      *"$CRASH_PATTERN"*)
        if [ "$CRASH_THRESHOLD" -le 1 ]; then
          count=1
        else
          now=$(date +%s)
          kept=""; count=0
          for t in $hits; do
            if [ $((now - t)) -lt "$CRASH_WINDOW" ]; then
              kept="$kept $t"; count=$((count + 1))
            fi
          done
          count=$((count + 1)); hits="$kept $now"
        fi
        if [ "$count" -ge "$CRASH_THRESHOLD" ]; then
          printf 'WATCHDOG: "%s" x%d within %ss >= %d - stopping container\n' \
            "$CRASH_PATTERN" "$count" "$CRASH_WINDOW" "$CRASH_THRESHOLD" >&2
          kill -TERM "$NEO4J_PID" 2>/dev/null
          i=0
          while kill -0 "$NEO4J_PID" 2>/dev/null && [ "$i" -lt 15 ]; do
            i=$((i + 1)); sleep 1
          done
          kill -KILL "$NEO4J_PID" 2>/dev/null
          exit 0
        fi
        ;;
    esac
  done < "$FIFO"
) &
SCANNER_PID=$!

# Exit when neo4j exits (covers the OOM flag and watchdog kills), propagating
# status so Rancher recreates the container.
wait "$NEO4J_PID"
STATUS=$?
kill -TERM "$SCANNER_PID" 2>/dev/null
exit "$STATUS"

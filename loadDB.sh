#!/bin/bash
# Restore the latest VFB release into /data (once per volume), then start Neo4j.
# Fails hard (exit 1) on any download/restore error so the orchestrator retries, instead of starting an empty DB.
set -euo pipefail

URL="${BACKUPURL:-http://data.virtualflybrain.org/archive/${BACKUPFILE}.tar.gz}"
WORK=/opt/VFB/backup

if [ ! -d /data/databases/neo4j ] || [ -z "$(ls -A /data/databases/neo4j 2>/dev/null)" ]; then
  echo "[pdb] restoring ${URL}"
  mkdir -p /data/databases /data/transactions "${WORK}"
  rm -rf "${WORK:?}"/*
  # The extracted backup is ~45 GB. Refuse unless WORK is a mounted scratch volume with room for it: extracting
  # into the container's own layer fills the node's system disk and gets every pod on the node evicted.
  need_kb=$(( ${RESTORE_MIN_FREE_GB:-55} * 1024 * 1024 ))
  free_kb=$(df -Pk "${WORK}" | awk 'NR==2{print $4}')
  if ! mountpoint -q "${WORK}" || [ "${free_kb}" -lt "${need_kb}" ]; then
    echo "[pdb] ${WORK} is not a mounted scratch volume with >= ${RESTORE_MIN_FREE_GB:-55} GB free (free: $((free_kb/1024/1024)) GB, mountpoint: $(mountpoint -q "${WORK}" && echo yes || echo no))."
    echo "[pdb] Mount a volume at ${WORK} (or clone a loaded golden volume to /data). Refusing to restore."
    exit 1
  fi
  # stream download straight into tar: no 5.7 GB intermediate file, one pass over the disk
  for attempt in 1 2 3; do
    if curl -fsSL --retry 3 --retry-delay 10 "${URL}" | tar -xz -C "${WORK}"; then break; fi
    echo "[pdb] download/extract attempt ${attempt} failed"; rm -rf "${WORK:?}"/*
    [ "${attempt}" = 3 ] && exit 1
    sleep 30
  done
  neo4j-admin restore --from="${WORK}/neo4j" --database=neo4j --force
  rm -rf "${WORK:?}"/*
  chown -R neo4j:neo4j /data
  echo "[pdb] restore complete"
fi

touch /logs/query.log 2>/dev/null || true
tail -F /logs/query.log 2>/dev/null >/proc/1/fd/1 &       # slow-query log -> container stdout (Loki)
rm -f /var/lib/neo4j/run/pdb-ready
/opt/VFB/post_start.sh >/proc/1/fd/1 2>&1 &                # warm-up + GDS projections + ready marker

exec /startup/docker-entrypoint.sh neo4j

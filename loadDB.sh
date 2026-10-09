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

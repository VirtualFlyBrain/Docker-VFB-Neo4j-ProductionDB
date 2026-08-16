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

# (Re)build the Circuit Browser per-connectome GDS projections once Neo4j is
# accepting queries. GDS projections are in-memory only, so this runs on every
# start (after the DB restore above). Backgrounded so it does not block Neo4j.
/opt/VFB/gds_projections.sh >> /var/lib/neo4j/logs/gds_projections.log 2>&1 &

exec /docker-entrypoint.sh neo4j

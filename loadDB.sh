#!/bin/sh
echo "set read only = ${NEOREADONLY} then launch neo4j service"
sed -i s/read_only=.*/read_only=${NEOREADONLY}/ ${NEOSERCONF} && \

echo 'Allow new neo4j2owl plugin to make changes..'
echo 'dbms.security.procedures.unrestricted=ebi.spot.neo4j2owl.*,apoc.*' >> ${NEOSERCONF}
#echo 'dbms.security.procedures.whitelist=ebi.spot.neo4j2owl.*,apoc.*' >> ${NEOSERCONF}

if [ -n "${BACKUPFILE}" ]; then
  if [ ! -d /data/databases/graph.db ]; then
    if [ ! -d /backup/DB-RESTORE.db ]; then
      echo 'Resore KB from archive backup'
      cd /opt/VFB/backup/
      rm /opt/VFB/backup/${BACKUPFILE}.tar.gz
      wget http://data.virtualflybrain.org/archive/${BACKUPFILE}.tar.gz 
      tar -xzvf ${BACKUPFILE}.tar.gz
      mkdir -p /backup/DB-RESTORE.db/
      find /opt/VFB/backup/ -name 'DB-RESTORE.db' -exec cp -vr "{}" /backup/ +
      rm -rf /opt/VFB/backup/*
      cd -
    fi
    if [ -d /backup/DB-RESTORE.db ]; then
      echo 'Resore KB from given backup'
      /var/lib/neo4j/bin/neo4j-admin restore --from=/backup/DB-RESTORE.db --force=true
    fi
  fi
fi

echo -e '\nSTARTING VFB KB SERVER\n' >> /var/lib/neo4j/logs/query.log

#Output the query log to docker log:
tail -f /var/lib/neo4j/logs/query.log >/proc/1/fd/1 &
exec /docker-entrypoint.sh neo4j

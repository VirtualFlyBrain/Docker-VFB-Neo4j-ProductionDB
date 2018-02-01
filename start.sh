#!/bin/sh

echo "setting read only = ${NEOREADONLY} and launching neo4j service"
sed -i s/read_only=.*/read_only=${NEOREADONLY}/ ${NEOSERCONF} && \
exec /docker-entrypoint.sh neo4j

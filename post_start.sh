#!/bin/bash
# After Neo4j accepts queries: warm the page cache, build the Circuit Browser GDS projections, then mark ready.
# Probes should require /var/lib/neo4j/run/pdb-ready so no traffic arrives at a cold or half-built copy.
set -u
CYPHER="cypher-shell -a bolt://localhost:7687 -u ${NEO4J_AUTH%%/*} -p ${NEO4J_AUTH#*/} --format plain"

echo "[pdb] waiting for Neo4j"
for i in $(seq 1 360); do echo "RETURN 1;" | $CYPHER >/dev/null 2>&1 && break; sleep 10; done

echo "[pdb] warming page cache (all stores + indexes)"
t=$(date +%s)
echo "CALL apoc.warmup.run(true, true, true) YIELD pageSize, totalTime RETURN pageSize, totalTime;" | $CYPHER || true
echo "[pdb] warm-up took $(( $(date +%s) - t ))s"

/opt/VFB/gds_projections.sh || { echo "[pdb] GDS projections failed"; exit 1; }

mkdir -p /var/lib/neo4j/run && touch /var/lib/neo4j/run/pdb-ready
echo "[pdb] READY"

#!/bin/sh
#
# (Re)build one named GDS graph projection per connectome for the VFB Circuit
# Browser, once Neo4j is accepting queries. Backgrounded from loadDB.sh.
#
# GDS in-memory projections are NOT persisted -- they are lost on every restart,
# so this runs on every container start (after the DB is restored and up).
# The Circuit Browser query (geppetto-vfb circuitBrowserConfiguration.js) runs
# gds.beta.shortestPath.yens.stream against these "cb_<connectome>" graphs
# instead of projecting the whole ~488k-node / ~34.7M-edge synapsed_to graph on
# every request.
#
set -u

USER="${GDS_NEO4J_USER:-neo4j}"
PASS="${GDS_NEO4J_PASSWORD:-vfb}"
CYPHER="cypher-shell -a bolt://localhost:7687 -u ${USER} -p ${PASS} --format plain"

echo "[gds] waiting for Neo4j to accept queries ..."
i=0
until echo "RETURN 1;" | $CYPHER >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -gt 180 ]; then
    echo "[gds] Neo4j not ready after 30m; giving up"
    exit 1
  fi
  sleep 10
done
echo "[gds] Neo4j ready; (re)building per-connectome projections"

SFS=$(printf 'MATCH (s:Connectome) RETURN s.short_form;\n' | $CYPHER 2>/dev/null \
        | tail -n +2 | tr -d '"' | tr -d '\r')

for SF in $SFS; do
  [ -z "$SF" ] && continue
  G="cb_${SF}"
  echo "[gds] ${G}"

  # drop any stale projection (in-memory catalog is global; a prior start may linger)
  printf "CALL gds.graph.exists('%s') YIELD exists WITH exists WHERE exists CALL gds.graph.drop('%s') YIELD graphName RETURN graphName;\n" \
    "$G" "$G" | $CYPHER >/dev/null 2>&1 || true

  # weight_p (= 5000 - synaptic weight) is the path cost so stronger connections
  # are shorter; raw weight kept for the client's display filter.
  printf "CALL gds.graph.create.cypher('%s', 'MATCH (n:Neuron:has_neuron_connectivity)-[:database_cross_reference]->(:Connectome {short_form:\"%s\"}) RETURN id(n) AS id', 'MATCH (:Connectome {short_form:\"%s\"})<-[:database_cross_reference]-(a:Neuron:has_neuron_connectivity)-[r:synapsed_to]->(b:Neuron:has_neuron_connectivity)-[:database_cross_reference]->(:Connectome {short_form:\"%s\"}) WHERE exists(r.weight) RETURN id(a) AS source, id(b) AS target, 5000 - r.weight[0] AS weight_p, r.weight[0] AS weight') YIELD graphName, nodeCount, relationshipCount RETURN graphName, nodeCount, relationshipCount;\n" \
    "$G" "$SF" "$SF" "$SF" | $CYPHER
done

echo "[gds] done. Catalog:"
printf 'CALL gds.graph.list() YIELD graphName, nodeCount, relationshipCount RETURN graphName, nodeCount, relationshipCount ORDER BY graphName;\n' | $CYPHER

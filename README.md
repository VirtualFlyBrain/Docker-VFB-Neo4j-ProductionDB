# docker-vfb-neo4j-productiondb

Neo4j server with the VFB production database (pdb) loaded from
`http://data.virtualflybrain.org/archive/VFB-PDB-v4.tar.gz` at first start.

## Branches
- `master` / `v4` — Neo4j 4.2 image used by the old Rancher (Cattle) stack.
- `pdb-k8s` — Neo4j 4.4 LTS build tuned for large, complex read-only queries on the Kubernetes cluster
  (talosconfig `apps/pdb`, docs/09-pdb.md). Pushes publish `virtualflybrain/docker-vfb-neo4j-productiondb:pdb-k8s`.

## pdb-k8s build
- Neo4j 4.4.48 enterprise, APOC 4.4.0.40 (sha256-checked), GDS 2.6.11 — all baked in; no plugin downloads at start.
- Query-plan cache on; slow-query log (>2 s) with CPU, allocation and page-cache detail.
- Memory defaults for a ~96 GiB pod: heap 31g, page cache 56g (whole store in RAM). Override with
  `NEO4J_dbms_memory_heap_max__size` / `NEO4J_dbms_memory_pagecache_size`.
- G1 GC. Set `-XX:ActiveProcessorCount=N` in `NEO4J_dbms_jvm_additional` per deployment — older JDKs size
  themselves from cgroup cpu.shares (the 4.2 image saw ONE cpu on Cattle).
- No statement timeout by default; set `NEO4J_dbms_transaction_timeout` on interactive deployments.
- Startup (`loadDB.sh`): stream-download + extract + `neo4j-admin restore` (fails hard on error), store upgrade
  from the 4.2 backup, then `post_start.sh` warms the page cache (`apoc.warmup.run`), builds the Circuit Browser
  GDS projections (`gds_projections.sh`), and touches `/var/lib/neo4j/run/pdb-ready`.
- Readiness: `test -f /var/lib/neo4j/run/pdb-ready` plus a query.

```
docker run -p 7474:7474 -p 7687:7687 \
  -e NEO4J_dbms_memory_heap_max__size=8g -e NEO4J_dbms_memory_heap_initial__size=8g -e NEO4J_dbms_memory_pagecache_size=48g \
  virtualflybrain/docker-vfb-neo4j-productiondb:pdb-k8s
```

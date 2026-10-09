# VFB production database (pdb) — build tuned for large, complex read-only queries on Kubernetes.
#
# Differences from the v4/master image (virtualflybrain/docker-vfb-neo4j:4.2-enterprise base):
#   * Neo4j 4.4 LTS (4.4.48) enterprise — pipelined runtime, newer planner; restores the existing 4.2 backup
#     and upgrades the store on first start (dbms.allow_upgrade).
#   * APOC and GDS baked in at matching versions, checksum-verified. Nothing is downloaded at start
#     except the database itself (the 4.2 image fetched APOC from GitHub on every start).
#   * Query-plan cache ON (the base image set dbms.query_cache_size=0, so every query was re-planned).
#   * Correct memory setting names (the old NEO4J_dbms_memory_heap_maxSize was silently ignored).
#   * Startup: streamed download+extract, hard failure if the restore fails, page-cache warm-up, then the
#     Circuit Browser GDS projections, then a ready marker (/var/lib/neo4j/run/pdb-ready) for probes.
FROM neo4j:4.4.48-enterprise

ARG APOC_VERSION=4.4.0.40
ARG APOC_SHA256=3ecb3bda4d4b1659a4dd0e02d75d7c3df44bbcee1354c4cb01527a6f807733ab
ARG GDS_VERSION=2.6.11

ENV NEO4J_ACCEPT_LICENSE_AGREEMENT=yes \
    NEO4J_AUTH=neo4j/vfb \
    BACKUPFILE=VFB-PDB-v4 \
    BACKUPURL="" \
    # read-only public copy
    NEO4J_dbms_read__only=true \
    NEO4J_dbms_allow__upgrade=true \
    NEO4J_dbms_security_procedures_unrestricted="apoc.*,gds.*" \
    NEO4J_dbms_security_procedures_allowlist="apoc.*,gds.*" \
    # memory — sized for one pod with ~96 GiB (override per deployment). 31g keeps compressed oops; the
    # page cache holds the whole store (41.7 GB on 2026-10-09) with room to grow.
    NEO4J_dbms_memory_heap_initial__size=31g \
    NEO4J_dbms_memory_heap_max__size=31g \
    NEO4J_dbms_memory_pagecache_size=56g \
    # planning: keep compiled plans (default 1000) — queries differ only in literals in many VFB clients
    NEO4J_dbms_query__cache__size=4000 \
    NEO4J_cypher_min__replan__interval=60s \
    # logging: slow queries only, with allocation + timing detail
    NEO4J_dbms_logs_query_enabled=INFO \
    NEO4J_dbms_logs_query_threshold=2s \
    NEO4J_dbms_logs_query_time__logging__enabled=true \
    NEO4J_dbms_logs_query_allocation__logging__enabled=true \
    NEO4J_dbms_logs_query_page__logging__enabled=true \
    NEO4J_dbms_track__query__cpu__time=true \
    # no statement timeout by default; the interactive deployment sets dbms.transaction.timeout
    NEO4J_dbms_transaction_timeout=0 \
    # G1 + exit on OOM (the orchestrator restarts the pod). Add -XX:ActiveProcessorCount=N per deployment.
    NEO4J_dbms_jvm_additional="-XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:+ParallelRefProcEnabled -XX:+ExitOnOutOfMemoryError -Dlog4j2.formatMsgNoLookups=true" \
    LOG4J_FORMAT_MSG_NO_LOOKUPS=true

RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates unzip \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL -o /var/lib/neo4j/plugins/apoc-${APOC_VERSION}-all.jar \
      https://github.com/neo4j-contrib/neo4j-apoc-procedures/releases/download/${APOC_VERSION}/apoc-${APOC_VERSION}-all.jar \
 && echo "${APOC_SHA256}  /var/lib/neo4j/plugins/apoc-${APOC_VERSION}-all.jar" | sha256sum -c - \
 && curl -fsSL -o /tmp/gds.zip https://graphdatascience.ninja/neo4j-graph-data-science-${GDS_VERSION}.zip \
 && unzip -q /tmp/gds.zip -d /var/lib/neo4j/plugins/ && rm /tmp/gds.zip \
 && ls -la /var/lib/neo4j/plugins/

COPY loadDB.sh post_start.sh gds_projections.sh /opt/VFB/
RUN chmod +x /opt/VFB/*.sh && mkdir -p /opt/VFB/backup && chmod 777 /opt/VFB/backup

ENTRYPOINT ["/opt/VFB/loadDB.sh"]

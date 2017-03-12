FROM neo4j:2.3-enterprise 

COPY graph.db /var/lib/neo4j/data/databases/graph.db

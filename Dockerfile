FROM neo4j:2.3-enterprise 

ADD http://virtualflybrain.org/public_resources/productionDB.tar /opt/

RUN tar -xzvf /opt/productionDB.tar && \
mv disk/data/neo4j/.ols/neo4j /var/lib/neo4j/data/databases/ && \
sed -i s/graph.db/neo4j/ /var/lib/neo4j/conf/neo4j-server.properties

RUN sed -i s/dbms.security.auth_enabled=true/dbms.security.auth_enabled=false/ /var/lib/neo4j/conf/neo4j-server.properties && \
echo 'read_only=true' >> /var/lib/neo4j/conf/neo4j-server.properties


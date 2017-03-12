FROM neo4j:2.3-enterprise 

ADD http://virtualflybrain.org/public_resources/productionDB.tar /opt/

RUN tar -xzvf /opt/productionDB.tar && \
sed -i 's|=data\/graph\.db|=\/disk\/data\/neo4j\/\.ols\/neo4j|' /var/lib/neo4j/conf/neo4j-server.properties && \
chmod -R 777 /disk && \
sed -i s/dbms.security.auth_enabled=true/dbms.security.auth_enabled=false/ /var/lib/neo4j/conf/neo4j-server.properties && \
echo 'read_only=false' >> /var/lib/neo4j/conf/neo4j-server.properties && \
sed -i s/#allow_store_upgrade=true/allow_store_upgrade=true/ /var/lib/neo4j/conf/neo4j.properties

VOLUME /disk

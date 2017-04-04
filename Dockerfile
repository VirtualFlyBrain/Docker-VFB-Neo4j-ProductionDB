FROM virtualflybrain/docker-vfb-neo4j:2.3-enterprise 

ADD http://virtualflybrain.org/public_resources/productionDB.tar /opt/

RUN cd / && tar -xzvf /opt/productionDB.tar && \
sed -i 's|=data\/graph\.db|=\/disk\/data\/neo4j\/\.ols\/neo4j|' ${NEOSERCONF} && \
chmod -R 777 /disk

VOLUME /disk

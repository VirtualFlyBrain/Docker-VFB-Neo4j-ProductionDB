FROM virtualflybrain/docker-vfb-neo4j:2.3-enterprise 

ADD http://data.virtualflybrain.org/archive/PDBbackup1.tar.gz /opt/

RUN cd / && tar -xzvf /opt/PDBbackup1.tar.gz && \
sed -i 's|=data\/graph\.db|=\/disk\/data\/neo4j\/\.ols\/neo4j|' ${NEOSERCONF} && \
chmod -R 777 /disk

VOLUME /disk

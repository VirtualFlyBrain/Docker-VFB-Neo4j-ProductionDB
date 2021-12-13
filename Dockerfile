FROM virtualflybrain/docker-vfb-neo4j:2.3-enterprise 

# Fix for log4j vulnerability
ENV LOG4J_FORMAT_MSG_NO_LOOKUPS=true
ENV NEO4J_dbms_jvm_additional="-Dlog4j2.formatMsgNoLookups=true -Dlog4j2.disable.jmx=true"

ADD http://data.virtualflybrain.org/archive/productionDB.tar.gz /opt/

RUN cd / && tar -xzvf /opt/productionDB.tar.gz && \
sed -i 's|=data\/graph\.db|=\/disk\/data\/neo4j\/\.ols\/neo4j|' ${NEOSERCONF} && \
chmod -R 777 /disk

VOLUME /disk

COPY start.sh /opt/VFB/

RUN chmod +x /opt/VFB/start.sh

ENTRYPOINT ["/opt/VFB/start.sh"]

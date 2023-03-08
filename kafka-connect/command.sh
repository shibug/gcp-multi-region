# Wait for Kafka Connect to be started
bash -c ' \
echo -e "\n\n=============\nWaiting for Kafka Connect to start listening on localhost ⏳\n=============\n"
while [ $(curl -s -o /dev/null -w %{http_code} http://localhost:8083/connectors) -ne 200 ] ; do
  echo -e "\t" $(date) " Kafka Connect listener HTTP state: " $(curl -s -o /dev/null -w %{http_code} http://localhost:8083/connectors) " (waiting for 200)"
  sleep 5
done
echo -e $(date) "\n\n--------------\n\o/ Kafka Connect is ready! Listener HTTP state: " $(curl -s -o /dev/null -w %{http_code} http://localhost:8083/connectors) "\n--------------\n"
'

# Make sure that the JDBC connectors are available:
curl -s localhost:8083/connector-plugins|jq '.[].class'|egrep 'Neo4jSinkConnector|MySqlConnector|ElasticsearchSinkConnector|JdbcSourceConnector|JdbcSinkConnector'

# Get a MySQL prompt
docker exec -it mysql bash -c 'mysql -u root -p$MYSQL_ROOT_PASSWORD demo'

# Look at the DB
SELECT * FROM ORDERS ORDER BY CREATE_TS DESC LIMIT 1\G

# Trigger data generator
docker exec mysql /data/02_populate_more_orders.sh

# Look at new rows
watch -n 1 -x docker exec -t mysql bash -c 'echo "SELECT * FROM ORDERS ORDER BY CREATE_TS DESC LIMIT 1 \G" | mysql -u root -p$MYSQL_ROOT_PASSWORD demo'

# Source Connector
curl -i -X PUT -H  "Content-Type:application/json" \
    http://localhost:8083/connectors/source-debezium-orders-00/config \
    -d '{
            "connector.class": "io.debezium.connector.mysql.MySqlConnector",
            "database.hostname": "mysql",
            "database.port": "3306",
            "database.user": "debezium",
            "database.password": "dbz",
            "database.server.id": "18859",
            "table.include.list": "demo.ORDERS",
            "schema.history.internal.kafka.bootstrap.servers": "pkc-3w22w.us-central1.gcp.confluent.cloud:9092",
            "schema.history.internal.kafka.topic": "schemahistory.demo",
            "schema.history.internal.consumer.security.protocol": "SASL_SSL",
            "schema.history.internal.consumer.sasl.mechanism": "PLAIN",
            "schema.history.internal.consumer.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username='FLAWK27UUYGHSORO' password='ZGleKIbERe56DVAJ0ltmHnMlWPc6jTcyvAVJ5jF6IMz5xdKokorVerwYwDmYxJWU';",
            "schema.history.internal.producer.security.protocol": "SASL_SSL",
            "schema.history.internal.producer.sasl.mechanism": "PLAIN",
            "schema.history.internal.producer.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username='FLAWK27UUYGHSORO' password='ZGleKIbERe56DVAJ0ltmHnMlWPc6jTcyvAVJ5jF6IMz5xdKokorVerwYwDmYxJWU';",            
            "topic.prefix": "shibu",
            "topic.creation.default.replication.factor": "3",
            "topic.creation.default.partitions": "1",
            "include.schema.changes": "true"
    }'

 # Check the status of the connector
curl -s "http://localhost:8083/connectors?expand=info&expand=status" | \
       jq '. | to_entries[] | [ .value.info.type, .key, .value.status.connector.state,.value.status.tasks[].state,.value.info.config."connector.class"]|join(":|:")' | \
       column -s : -t| sed 's/\"//g'| sort

# View the topic in the CLI:
kcat -C -s value=avro -t shibu.demo.ORDERS -o -10 -q -f 'key %k: %s\n\n'

# Stream to Cockroach
curl -i -X PUT -H  "Content-Type:application/json" \
    http://localhost:8083/connectors/sink-cockroachdb-orders-00/config \
    -d '{
            "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
            "topics": "shibu.demo.ORDERS",
            "connection.url": "jdbc:postgresql://34.72.138.31:26257/flowcrm?sslmode=verify-ca&sslcert=/data/client.root.crt&sslkey=/data/client.root.pk8&sslrootcert=/data/ca.crt",
            "connection.user": "root",
            "dialect.name": "PostgreSqlDatabaseDialect",
            "table.name.format": "public.orders",
            "pk.mode": "record_value",
            "pk.fields": "id",
            "insert.mode": "upsert",
            "auto.create": "true",
            "auto.evolve": "true",
            "transforms": "unwrap",
            "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
            "transforms.unwrap.drop.tombstones": "false"
        } '

# Stream to Postgres
curl -i -X PUT -H  "Content-Type:application/json" \
    http://localhost:8083/connectors/sink-postgres-orders-00/config \
    -d '{
            "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
            "topics": "mysql-debezium-asgard.demo.ORDERS",
            "connection.url": "jdbc:postgresql://34.170.47.253:5432/postgres",
            "connection.user": "postgres",
            "connection.password": "postgres",
            "table.name.format": "public.orders",
            "pk.mode": "record_value",
            "pk.fields": "id",
            "insert.mode": "upsert",
            "auto.create": "true",
            "auto.evolve": "true"
        } '

# Stream data to ElasticSearch
curl -i -X PUT -H  "Content-Type:application/json" \
    http://localhost:8083/connectors/sink-elastic-orders-00/config \
    -d '{
        "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
        "topics": "mysql-debezium-asgard.demo.ORDERS",
        "connection.url": "http://elasticsearch:9200",
        "type.name": "type.name=kafkaconnect",
        "key.ignore": "true",
        "schema.ignore": "true"
    }'

# Stream data to Neo4j
curl -i -X PUT -H  "Content-Type:application/json" \
    http://localhost:8083/connectors/sink-neo4j-orders-00/config \
    -d '{
            "connector.class": "streams.kafka.connect.sink.Neo4jSinkConnector",
            "topics": "mysql-debezium-asgard.demo.ORDERS",
            "neo4j.server.uri": "bolt://neo4j:7687",
            "neo4j.authentication.basic.username": "neo4j",
            "neo4j.authentication.basic.password": "connect1",
            "neo4j.topic.cypher.mysql-debezium-asgard.demo.ORDERS": "MERGE (city:city{city: event.delivery_city}) MERGE (customer:customer{id: event.customer_id, delivery_address: event.delivery_address, delivery_city: event.delivery_city, delivery_company: event.delivery_company}) MERGE (vehicle:vehicle{make: event.make, model:event.model}) MERGE (city)<-[:LIVES_IN]-(customer)-[:BOUGHT{order_total_usd:event.order_total_usd,order_id:event.id}]->(vehicle)"
        } '

# Delete connector        
curl -i -X DELETE http://localhost:8083/connectors/sink-cockroachdb-orders-00

----------------------------------------------------------------------------------
insert into orders values (date 'epoch' + interval '1511299894888 milliseconds', '13485', 'Item_7');

dki --name kafka-connect \
    -e CONNECT_PLUGIN_PATH=/usr/share/java,/usr/share/confluent-hub-components,/data/connect-jars \
    -e CONNECT_BOOTSTRAP_SERVERS=pkc-3w22w.us-central1.gcp.confluent.cloud:9092 -e CONNECT_REST_PORT=8083 -e CONNECT_GROUP_ID=kafka-connect \
    -e CONNECT_CONFIG_STORAGE_TOPIC=_connect-configs -e CONNECT_OFFSET_STORAGE_TOPIC=_connect-offsets -e CONNECT_STATUS_STORAGE_TOPIC=_connect-status \
    -e CONNECT_KEY_CONVERTER=org.apache.kafka.connect.json.JsonConverter -e CONNECT_VALUE_CONVERTER=org.apache.kafka.connect.json.JsonConverter \
    -e CONNECT_REST_ADVERTISED_HOST_NAME="kafka-connect" \
    -e CONNECT_LOG4J_APPENDER_STDOUT_LAYOUT_CONVERSIONPATTERN="[%d] %p %X{connector.context}%m (%c:%L)%n" \
    -e CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR="3" -e CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR="3" -e CONNECT_STATUS_STORAGE_REPLICATION_FACTOR="3" \
    -e CONNECT_SECURITY_PROTOCOL=SASL_SSL -e CONNECT_SASL_MECHANISM=PLAIN \
    -e CONNECT_SASL_JAAS_CONFIG="org.apache.kafka.common.security.plain.PlainLoginModule required username='I3O6EKLZ5SVNVGHP' password='BnvJE3ePW8gkW7/b9HDA1T96cJw741DoPEmLlEB8bfepn0N0xm7/92ib/8WeOXyL';" \
    -e CONNECT_REQUEST_TIMEOUT_MS=20000 -e CONNECT_RETRY_BACKOFF_MS=500 -e CONNECT_OFFSET_FLUSH_INTERVAL_MS=10000 \
    -v $PWD/data:/data \
    -p 8083:8083 confluentinc/cp-kafka-connect \
    bash -c "echo \"Installing Connector\"; confluent-hub install --no-prompt confluentinc/kafka-connect-jdbc:10.6.0; echo \"Launching Kafka Connect worker\"; /etc/confluent/docker/run"

# Source Connector
curl -i -X PUT -H  "Content-Type:application/json" \
    http://localhost:8083/connectors/source-debezium-orders-00/config \
    -d '{
            "connector.class": "io.debezium.connector.mysql.MySqlConnector",
            "database.hostname": "mysql",
            "database.port": "3306",
            "database.user": "debezium",
            "database.password": "dbz",
            "database.server.id": "42",
            "table.whitelist": "demo.orders",
            "topic.prefix": "mysql-debezium-asgard",
            "schema.history.internal.kafka.bootstrap.servers": "broker:29092",
            "schema.history.internal.kafka.topic": "dbhistory.demo" ,
            "decimal.handling.mode": "double",
            "include.schema.changes": "true"
    }'

curl -i -X PUT -H  "Content-Type:application/json" \
    http://localhost:8083/connectors/sink-elastic-orders-00/config \
    -d '{
        "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
        "topics": "mysql-debezium-asgard.demo.ORDERS",
        "connection.url": "http://elasticsearch:9200",
        "type.name": "type.name=kafkaconnect",
        "key.ignore": "true",
        "schema.ignore": "true"
    }'
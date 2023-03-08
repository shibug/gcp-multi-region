# Initialize cockroach DB
k -n cockroachdb exec -it cockroachdb-0 -- /cockroach/cockroach init --certs-dir=/cockroach/cockroach-certs

# Connect via cockroach SQL client
cockroach sql --url="postgres://34.121.226.93:26257/flowcrm?sslmode=verify-ca&sslcert=certs/client.root.crt&sslkey=certs/client.root.key&sslrootcert=certs/ca.crt"
End-to-end Big Data ingest pipeline using Apache NiFi + Cassandra on Google Cloud.
GCS landing bucket → NiFi ingest/transform/validate → Cassandra storage
Includes schema setup, data quality checks, logging, and performance/query testing
Infra can be provisioned using Terraform (GCP resources + cluster setup)

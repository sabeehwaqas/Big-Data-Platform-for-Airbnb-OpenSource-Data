#!/bin/bash

# Project and zone information
PROJECT="mybigdataproject-485818"
ZONE="europe-north1-a"

# List the instances you want to stop
INSTANCES=("cassandra-node-1" "cassandra-node-2" "cassandra-node-3" "nifi-node")

# Loop through each instance and stop it
for INSTANCE in "${INSTANCES[@]}"; do
    echo "Stopping $INSTANCE..."
    gcloud compute instances stop "$INSTANCE" --zone "$ZONE" --project "$PROJECT"
done

echo "All instances stopped."

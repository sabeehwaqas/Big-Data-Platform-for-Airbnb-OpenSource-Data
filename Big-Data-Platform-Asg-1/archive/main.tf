provider "google" {
  project     = "mybigdataproject-485818"
  credentials = file("creds.json")
  region      = "europe-north1"
  zone        = "europe-north1-a"
}

# Number of Cassandra nodes
variable "instance_count" {
  default = 3
}

# VPC Network
resource "google_compute_network" "default" {
  name                    = "cassandra-network"
  auto_create_subnetworks  = false  # We define subnetwork manually
}

# Subnetwork for the VMs
resource "google_compute_subnetwork" "default" {
  name          = "cassandra-subnetwork"
  region        = "europe-north1"
  network       = google_compute_network.default.id
  ip_cidr_range = "10.0.0.0/24"
}

# Internal IPs for each Cassandra node
resource "google_compute_address" "cassandra_internal" {
  count        = var.instance_count
  name         = "cassandra-internal-${count.index + 1}"
  region       = "europe-north1"
  subnetwork   = google_compute_subnetwork.default.id
  address_type = "INTERNAL"
  address      = "10.0.0.${10 + count.index}"
}

# Firewall rule to allow SSH, CQL, and intra-cluster communication
resource "google_compute_firewall" "allow_ssh_cql" {
  name    = "allow-ssh-cql"
  network = google_compute_network.default.id

  allow {
    protocol = "tcp"
    ports    = ["22", "9042"]  # SSH + CQL
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_cassandra_internode" {
  name    = "allow-cassandra-internode"
  network = google_compute_network.default.id

  allow {
    protocol = "tcp"
    ports    = ["7000", "7001", "7199", "9160"]  # Internode communication
  }

  source_ranges = ["10.0.0.0/24"]  # Only allow traffic from the subnet
}

# VM Instances for Cassandra Nodes
resource "google_compute_instance" "cassandra" {
  count        = var.instance_count
  name         = "cassandra-node-${count.index + 1}"
  machine_type = "e2-medium"
  zone         = "europe-north1-a"
  tags         = ["cassandra-node"]

  boot_disk {
    initialize_params {
      image = "ubuntu-2204-lts"  # Use a stable Ubuntu image (adjust the version)
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.default.id
    network_ip = google_compute_address.cassandra_internal[count.index].address
    access_config {}  # Assign public IP if needed for SSH access
  }

  metadata_startup_script = <<-EOT
#!/bin/bash
set -euxo pipefail

# Update and install Docker
sudo apt-get update
sudo apt-get install -y docker.io

# Enable and start Docker service
sudo systemctl enable docker
sudo systemctl start docker

# Create the custom Docker network (if not already created)
sudo docker network create cassandra-network || true

# Pull the official Apache Cassandra Docker image
sudo docker pull cassandra:4.0

# Get the VM's internal IP
NODE_IP="$(hostname -I | awk '{print $1}')"

# Seed nodes are the internal IPs of the other VMs
SEEDS="${join(",", google_compute_address.cassandra_internal[*].address)}"

# Run Cassandra container using host network
sudo docker run -d --name cassandra-node-${count.index + 1} --restart unless-stopped --network host \
  -e CASSANDRA_CLUSTER_NAME="CassandraCluster" \
  -e CASSANDRA_LISTEN_ADDRESS="$NODE_IP" \
  -e CASSANDRA_RPC_ADDRESS="0.0.0.0" \
  -e CASSANDRA_BROADCAST_RPC_ADDRESS="$NODE_IP" \
  -e CASSANDRA_SEEDS="$SEEDS" \
  cassandra:4.0

# Check if Cassandra container is running
if ! sudo docker ps | grep cassandra; then
  echo "Cassandra container failed to start. Exiting."
  exit 1
else
  echo "Cassandra is running successfully in Docker."
fi
  EOT
}

# Output to display the internal IPs of the created instances
output "cassandra_instance_ips" {
  value = [for instance in google_compute_instance.cassandra : instance.network_interface[0].network_ip]
}

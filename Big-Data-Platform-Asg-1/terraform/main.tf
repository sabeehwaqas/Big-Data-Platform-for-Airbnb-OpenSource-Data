provider "google" {
  project     = "mybigdataproject-485818"
  credentials = file("creds.json")
  region      = "europe-north1"
  zone        = "europe-north1-a"
}

resource "google_project_service" "iam_api" {
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}
resource "google_project_service" "cloudresourcemanager_api" {
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

#GCP storage

variable "bucket_suffix" {
  description = "Suffix to make the bucket name globally unique"
  type        = string
  default     = "485818"
}

resource "google_storage_bucket" "landing_bucket" {
  name     = "mysimbdp-landing-${var.bucket_suffix}"
  location = "EU"

  uniform_bucket_level_access = true
  force_destroy               = true
}

#creating the needed folder in gcp storage
resource "google_storage_bucket_object" "landing_dir" {
  bucket  = google_storage_bucket.landing_bucket.name
  name    = "landing/"
  content = " "
}

resource "google_storage_bucket_object" "landing_raw_dir" {
  bucket  = google_storage_bucket.landing_bucket.name
  name    = "landing/raw/"
  content = " "
}

resource "google_storage_bucket_object" "landing_processed_dir" {
  bucket  = google_storage_bucket.landing_bucket.name
  name    = "landing/processed/"
  content = " "
}

resource "google_storage_bucket_object" "landing_failed_dir" {
  bucket  = google_storage_bucket.landing_bucket.name
  name    = "landing/failed/"
  content = " "
}

#admin user to access the storage
resource "google_storage_bucket_iam_member" "admin_full_access" {
  bucket = google_storage_bucket.landing_bucket.name
  role   = "roles/storage.admin"
  member = "user:sabeeh.waqas@aalto.fi"
}

#nifi SA for storage access
resource "google_service_account" "nifi_sa" {
  account_id   = "nifi-landing-sa"
  display_name = "NiFi access to landing prefixes"

  depends_on = [
    google_project_service.iam_api,
    google_project_service.cloudresourcemanager_api
  ]
}


# Number of Cassandra nodes
variable "instance_count" {
  default = 3
}

# VPC Network
resource "google_compute_network" "default" {
  name                    = "cassandra-network"
  auto_create_subnetworks = false
}

# Subnetwork for the VMs
resource "google_compute_subnetwork" "default" {
  name          = "cassandra-subnetwork"
  region        = "europe-north1"
  network       = google_compute_network.default.id
  ip_cidr_range = "10.0.0.0/24"
}

# -------------------------
# Static INTERNAL IPs
# -------------------------
resource "google_compute_address" "cassandra_internal" {
  count        = var.instance_count
  name         = "cassandra-internal-${count.index + 1}"
  region       = "europe-north1"
  subnetwork   = google_compute_subnetwork.default.id
  address_type = "INTERNAL"
  address      = "10.0.0.${10 + count.index}"
}

resource "google_compute_address" "nifi_internal" {
  name         = "nifi-internal"
  region       = "europe-north1"
  subnetwork   = google_compute_subnetwork.default.id
  address_type = "INTERNAL"
  address      = "10.0.0.50"
}

# Static PUBLIC IP for NiFi Web UI
resource "google_compute_address" "nifi_public" {
  name   = "nifi-public"
  region = "europe-north1"
}

# -------------------------
# FIREWALLS
# Goals:
# - Cassandra: SSH from internet OK, CQL NOT exposed publicly
# - NiFi: Web UI exposed publicly
# - NiFi -> Cassandra: allow CQL (9042) privately
# -------------------------

# SSH to Cassandra (public)
resource "google_compute_firewall" "allow_ssh_cassandra" {
  name    = "allow-ssh-cassandra"
  network = google_compute_network.default.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["cassandra-node"]
}

# SSH to Nifi (public)
resource "google_compute_firewall" "allow_ssh_nifi" {
  name    = "allow-ssh-nifi"
  network = google_compute_network.default.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["nifi-node"]
}

# Allow NiFi Web UI from the internet
resource "google_compute_firewall" "allow_nifi_web" {
  name    = "allow-nifi-web"
  network = google_compute_network.default.id

  allow {
    protocol = "tcp"
    ports    = ["8080", "8443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["nifi-node"]
}

# Cassandra internode (only within subnet, only to cassandra nodes)
resource "google_compute_firewall" "allow_cassandra_internode" {
  name    = "allow-cassandra-internode"
  network = google_compute_network.default.id

  allow {
    protocol = "tcp"
    ports    = ["7000", "7001", "7199", "9160"]
  }

  source_ranges = ["10.0.0.0/24"]
  target_tags   = ["cassandra-node"]
}

# CQL access ONLY from NiFi to Cassandra (private)
resource "google_compute_firewall" "allow_cql_from_nifi" {
  name    = "allow-cql-from-nifi"
  network = google_compute_network.default.id

  allow {
    protocol = "tcp"
    ports    = ["9042"]
  }

  source_tags = ["nifi-node"]
  target_tags = ["cassandra-node"]
}

# -------------------------
# VM: Cassandra nodes
# -------------------------
resource "google_compute_instance" "cassandra" {
  count        = var.instance_count
  name         = "cassandra-node-${count.index + 1}"
  machine_type = "e2-medium"
  zone         = "europe-north1-a"
  tags         = ["cassandra-node"]

  boot_disk {
    initialize_params {
      image = "ubuntu-2204-lts"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.default.id
    network_ip = google_compute_address.cassandra_internal[count.index].address

    # Public IP so you can SSH
    access_config {}
  }

  metadata_startup_script = <<-EOT
#!/bin/bash
set -euxo pipefail

apt-get update
apt-get install -y docker.io
systemctl enable docker
systemctl start docker

docker pull cassandra:4.0

NODE_IP="$(hostname -I | awk '{print $1}')"
SEEDS="${join(",", google_compute_address.cassandra_internal[*].address)}"

docker rm -f cassandra-node-${count.index + 1} || true

docker run -d --name cassandra-node-${count.index + 1} --restart unless-stopped --network host \
  -e CASSANDRA_CLUSTER_NAME="CassandraCluster" \
  -e CASSANDRA_LISTEN_ADDRESS="$NODE_IP" \
  -e CASSANDRA_RPC_ADDRESS="0.0.0.0" \
  -e CASSANDRA_BROADCAST_RPC_ADDRESS="$NODE_IP" \
  -e CASSANDRA_SEEDS="$SEEDS" \
  cassandra:4.0

docker ps | grep -q cassandra-node-${count.index + 1}
echo "Cassandra node ${count.index + 1} up on $${NODE_IP}"
  EOT
}

output "cassandra_instance_internal_ips" {
  value = [for instance in google_compute_instance.cassandra : instance.network_interface[0].network_ip]
}

output "cassandra_instance_public_ips" {
  value = [for instance in google_compute_instance.cassandra : instance.network_interface[0].access_config[0].nat_ip]
}

# -------------------------
# VM: NiFi node
# -------------------------
resource "google_compute_instance" "nifi" {
  name                      = "nifi-node"
  machine_type              = "e2-medium"
  zone                      = "europe-north1-a"
  tags                      = ["nifi-node"]
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "ubuntu-2204-lts"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.default.id
    network_ip = google_compute_address.nifi_internal.address

    # Static public IP for web UI
    access_config {
      nat_ip = google_compute_address.nifi_public.address
    }
  }

  metadata_startup_script = <<-EOT
#!/bin/bash
set -euxo pipefail

NIFI_IMAGE="apache/nifi:latest"
NIFI_NAME="nifi"

# Single-user creds (password must be 12+ chars)
NIFI_USER="sabeeh"
NIFI_PASS="sabeehsabeeh"

apt-get update
apt-get install -y docker.io
systemctl enable docker
systemctl start docker

# Get this VM's PUBLIC IP from GCP metadata (reliable)
PUBLIC_IP="$(curl -fsH "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip")"

mkdir -p /opt/nifi/{db,flowfile_repo,content_repo,provenance_repo,state,logs}
chmod -R 777 /opt/nifi

docker pull "$${NIFI_IMAGE}"

# Remove old container if present
docker rm -f "$${NIFI_NAME}" || true

# Run NiFi (HTTPS 8443)
docker run -d --name "$${NIFI_NAME}" --restart unless-stopped \
  -p 8443:8443 \
  -e SINGLE_USER_CREDENTIALS_USERNAME="$${NIFI_USER}" \
  -e SINGLE_USER_CREDENTIALS_PASSWORD="$${NIFI_PASS}" \
  -e NIFI_WEB_HTTPS_HOST="0.0.0.0" \
  -e NIFI_WEB_PROXY_HOST="$${PUBLIC_IP}:8443" \
  -v /opt/nifi/db:/opt/nifi/nifi-current/database_repository \
  -v /opt/nifi/flowfile_repo:/opt/nifi/nifi-current/flowfile_repository \
  -v /opt/nifi/content_repo:/opt/nifi/nifi-current/content_repository \
  -v /opt/nifi/provenance_repo:/opt/nifi/nifi-current/provenance_repository \
  -v /opt/nifi/state:/opt/nifi/nifi-current/state \
  -v /opt/nifi/logs:/opt/nifi/nifi-current/logs \
  "$${NIFI_IMAGE}"

# Quick check
sleep 8
docker ps | grep -q "$${NIFI_NAME}"
echo "NiFi should be available at: https://$${PUBLIC_IP}:8443/nifi"
EOT

  service_account {
    email  = google_service_account.nifi_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }




}
# NiFi can access only landing/{raw,processed,failed}/
resource "google_storage_bucket_iam_member" "nifi_landing_prefix_access" {
  bucket = google_storage_bucket.landing_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.nifi_sa.email}"

  condition {
    title       = "nifi-landing-prefixes"
    description = "Allow NiFi only landing/raw, landing/processed, landing/failed"
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.landing_bucket.name}/objects/landing/raw/\") || resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.landing_bucket.name}/objects/landing/processed/\") || resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.landing_bucket.name}/objects/landing/failed/\")"
  }
}



output "nifi_public_ip" {
  value = google_compute_instance.nifi.network_interface[0].access_config[0].nat_ip
}

output "landing_bucket_name" {
  value = google_storage_bucket.landing_bucket.name
}

output "nifi_service_account_email" {
  value = google_service_account.nifi_sa.email
}

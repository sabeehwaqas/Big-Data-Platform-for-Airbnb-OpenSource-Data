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
#Zones

variable "zones" {
  description = "List of zones for Cassandra nodes"
  type        = list(string)
  default     = ["europe-north1-a", "europe-north1-b", "europe-north1-c"] # List of zones
}

# -------------------------
# GCS landing bucket
# -------------------------
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

resource "google_storage_bucket_iam_member" "admin_full_access" {
  bucket = google_storage_bucket.landing_bucket.name
  role   = "roles/storage.admin"
  member = "user:sabeeh.waqas@aalto.fi"
}

# -------------------------
# NiFi service account
# -------------------------
resource "google_service_account" "nifi_sa" {
  account_id   = "nifi-landing-sa"
  display_name = "NiFi access to landing prefixes"

  depends_on = [
    google_project_service.iam_api,
    google_project_service.cloudresourcemanager_api
  ]
}

# NiFi can access only landing/{raw,processed,failed}/
resource "google_storage_bucket_iam_member" "nifi_landing_prefix_access" {
  bucket = google_storage_bucket.landing_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.nifi_sa.email}"

  condition {
    title       = "nifi-landing-prefixes"
    description = "Allow NiFi only objects under landing/"
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.landing_bucket.name}/objects/landing/\")"
  }

}
# Allow NiFi service account to LIST objects in the bucket (required for ListGCSBucket)
resource "google_storage_bucket_iam_member" "nifi_list_objects" {
  bucket = google_storage_bucket.landing_bucket.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.nifi_sa.email}"
}

# -------------------------
# Network
# -------------------------
variable "instance_count" {
  default = 3
}

resource "google_compute_network" "default" {
  name                    = "cassandra-network-unique"
  auto_create_subnetworks = false
}

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

resource "google_compute_address" "nifi_public" {
  name   = "nifi-public"
  region = "europe-north1"
}

# -------------------------
# Firewalls
# -------------------------
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

resource "google_compute_firewall" "allow_cql_from_nifi" {
  name    = "allow-cql-from-nifi"
  network = google_compute_network.default.id

  allow {
    protocol = "tcp"
    ports    = ["9042"]
  }

  source_ranges = ["0.0.0.0/0"]

  source_tags = ["nifi-node"]
  target_tags = ["cassandra-node"]
}

# -------------------------
# Cassandra VMs
# -------------------------
resource "google_compute_instance" "cassandra" {
  count        = var.instance_count
  name         = "cassandra-node-${count.index + 1}"
  machine_type = "e2-medium"
  zone         = element(var.zones, count.index % length(var.zones))
  tags         = ["cassandra-node"]

  boot_disk {
    initialize_params {
      image = "ubuntu-2204-lts"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.default.id
    network_ip = google_compute_address.cassandra_internal[count.index].address
    access_config {}
  }

  metadata_startup_script = <<-EOT
#!/bin/bash
set -euxo pipefail

# Update system and install dependencies
apt-get update
apt-get install -y docker.io curl
systemctl enable docker
systemctl start docker

# Increase the vm.max_map_count and RLIMIT_MEMLOCK
echo "vm.max_map_count=1048575" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Set RLIMIT_MEMLOCK to unlimited
echo "* soft memlock unlimited" | sudo tee -a /etc/security/limits.conf
echo "* hard memlock unlimited" | sudo tee -a /etc/security/limits.conf

# Ensure Docker is working and pull Cassandra image
docker pull cassandra:4.0

# Use Terraform-known static internal IPs (no bash command substitution)
NODE_IP="${google_compute_address.cassandra_internal[count.index].address}"
SEEDS="${join(",", google_compute_address.cassandra_internal[*].address)}"

docker rm -f cassandra-node-${count.index + 1} || true

docker run -d --name cassandra-node-${count.index + 1} --restart unless-stopped --network host \
  -e CASSANDRA_CLUSTER_NAME="CassandraCluster" \
  -e CASSANDRA_LISTEN_ADDRESS="$${NODE_IP}" \
  -e CASSANDRA_RPC_ADDRESS="0.0.0.0" \
  -e CASSANDRA_BROADCAST_RPC_ADDRESS="$${NODE_IP}" \
  -e CASSANDRA_SEEDS="$${SEEDS}" \
  cassandra:4.0

# Increase the vm.max_map_count setting for all nodes to improve Cassandra performance
sysctl -w vm.max_map_count=1048575

sleep 5
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
# NiFi VM
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
    access_config {
      nat_ip = google_compute_address.nifi_public.address
    }
  }

  metadata_startup_script = <<-EOT
#!/bin/bash
set -euxo pipefail

NIFI_IMAGE="apache/nifi:2.7.2"
NIFI_NAME="nifi"

NIFI_USER="sabeeh"
NIFI_PASS="sabeehsabeeh"

apt-get update
apt-get install -y docker.io curl
systemctl enable docker
systemctl start docker

# Use Terraform-known static public IP (avoid metadata curl escaping issues)
PUBLIC_IP="${google_compute_address.nifi_public.address}"

mkdir -p /opt/nifi/{db,flowfile_repo,content_repo,provenance_repo,state,logs,jdbc}
chmod -R 777 /opt/nifi

JDBC_DIR="/opt/nifi/jdbc"
mkdir -p "$${JDBC_DIR}"
chmod 755 "$${JDBC_DIR}"

# -------------------------
# Download JDBC + dependencies (idempotent)
# -------------------------
download() {
  local url="$1"
  local out="$2"
  if [ ! -f "$${out}" ]; then
    curl -fL "$${url}" -o "$${out}"
  fi
}

# 1) Cassandra JDBC wrapper
WRAP_VER="4.16.1"
download "https://repo1.maven.org/maven2/com/ing/data/cassandra-jdbc-wrapper/$${WRAP_VER}/cassandra-jdbc-wrapper-$${WRAP_VER}.jar" \
         "$${JDBC_DIR}/cassandra-jdbc-wrapper-$${WRAP_VER}.jar"

# 2) Caffeine (required by wrapper)
CAF_VER="2.9.3"
download "https://repo1.maven.org/maven2/com/github/ben-manes/caffeine/caffeine/$${CAF_VER}/caffeine-$${CAF_VER}.jar" \
         "$${JDBC_DIR}/caffeine-$${CAF_VER}.jar"

# 3) DataStax Java driver core (provides DriverOption)
DS_VER="4.17.0"
download "https://repo1.maven.org/maven2/com/datastax/oss/java-driver-core/$${DS_VER}/java-driver-core-$${DS_VER}.jar" \
         "$${JDBC_DIR}/java-driver-core-$${DS_VER}.jar"

# 4) DataStax shaded guava (note: different versioning)
GUAVA_SHADED_VER="25.1-jre"
download "https://repo1.maven.org/maven2/com/datastax/oss/java-driver-shaded-guava/$${GUAVA_SHADED_VER}/java-driver-shaded-guava-$${GUAVA_SHADED_VER}.jar" \
         "$${JDBC_DIR}/java-driver-shaded-guava-$${GUAVA_SHADED_VER}.jar"

# 5) Typesafe config
CONF_VER="1.4.3"
download "https://repo1.maven.org/maven2/com/typesafe/config/$${CONF_VER}/config-$${CONF_VER}.jar" \
         "$${JDBC_DIR}/config-$${CONF_VER}.jar"

# 6) Native protocol (note: different versioning than driver core)
NP_VER="1.5.1"
download "https://repo1.maven.org/maven2/com/datastax/oss/native-protocol/$${NP_VER}/native-protocol-$${NP_VER}.jar" \
         "$${JDBC_DIR}/native-protocol-$${NP_VER}.jar"

# 7) Jackson (needed by driver/wrapper in NiFi DBCP classloader)
JACKSON_VER="2.17.2"
download "https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-core/$${JACKSON_VER}/jackson-core-$${JACKSON_VER}.jar" \
         "$${JDBC_DIR}/jackson-core-$${JACKSON_VER}.jar"
download "https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-databind/$${JACKSON_VER}/jackson-databind-$${JACKSON_VER}.jar" \
         "$${JDBC_DIR}/jackson-databind-$${JACKSON_VER}.jar"
download "https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-annotations/$${JACKSON_VER}/jackson-annotations-$${JACKSON_VER}.jar" \
         "$${JDBC_DIR}/jackson-annotations-$${JACKSON_VER}.jar"

# 8) Semver4J providing org.semver4j.Semver (avoid com.vdurmont confusion)
ORG_SEMVER_VER="6.0.0"
download "https://repo1.maven.org/maven2/org/semver4j/semver4j/$${ORG_SEMVER_VER}/semver4j-$${ORG_SEMVER_VER}.jar" \
         "$${JDBC_DIR}/org-semver4j-$${ORG_SEMVER_VER}.jar"

# 9) Netty modules (more reliable than netty-all for classloading)
NETTY_VER="4.1.108.Final"
for a in netty-common netty-buffer netty-transport netty-handler netty-codec netty-resolver netty-transport-native-unix-common; do
  download "https://repo1.maven.org/maven2/io/netty/$${a}/$${NETTY_VER}/$${a}-$${NETTY_VER}.jar" \
           "$${JDBC_DIR}/$${a}-$${NETTY_VER}.jar"
done

chmod 644 "$${JDBC_DIR}"/*.jar || true
echo "JDBC dir contents:"
ls -lh "$${JDBC_DIR}"

docker pull "$${NIFI_IMAGE}"
docker rm -f "$${NIFI_NAME}" || true

docker run -d --name "$${NIFI_NAME}" --restart unless-stopped \
  -p 8443:8443 \
  -e SINGLE_USER_CREDENTIALS_USERNAME="$${NIFI_USER}" \
  -e SINGLE_USER_CREDENTIALS_PASSWORD="$${NIFI_PASS}" \
  -e NIFI_WEB_HTTPS_HOST="0.0.0.0" \
  -e NIFI_WEB_PROXY_HOST="$${PUBLIC_IP}:8443" \
  -v /opt/nifi/jdbc:/opt/nifi/jdbc:ro \
  -v /opt/nifi/db:/opt/nifi/nifi-current/database_repository \
  -v /opt/nifi/flowfile_repo:/opt/nifi/nifi-current/flowfile_repository \
  -v /opt/nifi/content_repo:/opt/nifi/nifi-current/content_repository \
  -v /opt/nifi/provenance_repo:/opt/nifi/nifi-current/provenance_repository \
  -v /opt/nifi/state:/opt/nifi/nifi-current/state \
  -v /opt/nifi/logs:/opt/nifi/nifi-current/logs \
  "$${NIFI_IMAGE}"

sleep 10
docker ps | grep -q "$${NIFI_NAME}"
echo "NiFi should be available at: https://$${PUBLIC_IP}:8443/nifi"
EOT


  service_account {
    email  = google_service_account.nifi_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  depends_on = [
    google_storage_bucket_iam_member.nifi_landing_prefix_access
  ]
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

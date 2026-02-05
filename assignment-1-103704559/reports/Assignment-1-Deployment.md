# Deployment / Installation Guide (to run the assignment)

This guide explains how to **deploy the infrastructure**, **initialize Cassandra**, and **run the NiFi ingestion pipeline** for this assignment.

---

### 1) Prerequisites (install locally)

Install the following on your machine:

- **Python** (recommended **3.12+**)
- **Terraform**
- **Google Cloud SDK (`gcloud`)**
- Python package: **`cassandra-driver`**
  - `pip install cassandra-driver`

---

### 2) Google Cloud setup

1. Create / use a **Google Cloud account**
2. Create a **Google Cloud project**
3. In `main.tf`, update the **project name / project_id** to your project

---

### 3) Create Terraform service account + credentials

1. Create a **Service Account** for Terraform
2. Grant it **Editor** role (as required by this assignment setup)
3. Create a **JSON key**
4. Save the key file here:

`./MyBigDataProj/Big-Data-Platform-Asg-1/terraform/creds.json`

---

### 4) Provision infrastructure with Terraform

1. Open a terminal and go to the Terraform directory:
   - `./MyBigDataProj/Big-Data-Platform-Asg-1/terraform/`
2. Run:
   - `terraform apply`
3. After Terraform prints **“Apply complete!”**, wait
   NOTE: wait **~5 minutes** to ensure instances/services fully start.

Terraform outputs will include important IPs (e.g., **NiFi public IP**, Cassandra node IPs).

---

### 5) Upload source data to Cloud Storage

1. Open **Google Cloud Console → Cloud Storage**
2. Find the bucket: **`mysimbdp-landing-485818`**
3. Upload the source dataset into:

`mysimbdp-landing/landing/raw/`

Sample data is located at:

`./MyBigDataProj/assignment-1-103704559/data`

---

### 6) Initialize Cassandra schema

1. Open:

`./MyBigDataProj/Big-Data-Platform-Asg-1/initiate.py`

2. Update the Cassandra node **IP address** in the script
3. Run:

`python initiate.py`

This script creates the required **keyspace/table schema** on the Cassandra nodes.

---

### 7) Open NiFi UI

1. From Terraform output, copy the **NiFi public IP**
2. Open in browser:

`https://<NIFI_PUBLIC_IP>:8443/nifi/#/`

3. If the browser warns about security, click **Advanced → Proceed**
4. Login:
   - **Username:** `sabeeh`
   - **Password:** `sabeehsabeeh`

---

### 8) Import the NiFi flow

1. In NiFi, click the **Process Group** icon (top toolbar)
2. Click **Import** (right side of the dialog)
3. Select the flow JSON:

`./MyBigDataProj/Nifi Arch/DataIngest.json`

4. The process group will appear. **Double-click** to enter it.

---

### 9) Enable controller services and run the pipeline

1. Inside the process group, open the **PutDatabase** process
2. Locate **DBCPConnectionPool** (Database Connection Pooling Service)
3. Click the **3 dots → “Go to service”**
4. Enable all required controller services:
   - Click the **3 dots** next to each service → **Enable**
5. Go back to the process group (top-left: **Back to process group**)
6. Click **Start** to run the whole pipeline

**Note:** You may see an error like:  
`PutDatabaseRecord ... Routing to failure.: java.lang.NullPointerException`  
This is caused by corrupt input rows and is expected; the pipeline already routes such rows to the **failed folder** in Cloud Storage.

---

### 10) Verify data in Cassandra

To check inserted data, connect using `cqlsh`:

`cqlsh <CASSANDRA_NODE_IP> 9042`

Then query your keyspace/tables to verify ingestion.

---

# ─────────────────────────────────────────────────────────────
# GCP Project Configuration — Jakarta Region
# ─────────────────────────────────────────────────────────────
# IMPORTANT: Ganti project_id dengan GCP Project ID kamu
project_id = "project-065701e7-213d-458b-a83"

# Region Jakarta
region = "asia-southeast2"

# Zone Jakarta (pilih a, b, atau c)
zone = "asia-southeast2-a"

# Cluster & Network
gke_cluster_name = "gke-main"
vpc_name         = "gke-vpc"
subnet_name      = "gke-subnet"

# CIDR Ranges
subnet_cidr   = "10.0.0.0/16"
pods_cidr     = "10.1.0.0/16"
services_cidr = "10.2.0.0/16"

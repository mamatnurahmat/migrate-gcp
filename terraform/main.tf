provider "google" {
  project     = var.project_id
  region      = var.region
  # credentials = file("${path.module}/credentials.json") # Menggunakan ADC agar lebih aman & kompatibel dengan policy GCP
}

# =============================================================
# VPC NETWORK
# =============================================================
resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
  description             = "VPC for GKE cluster — Jakarta"
}

resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
  description   = "Primary subnet for GKE nodes — Jakarta (asia-southeast2)"

  # Secondary ranges wajib untuk GKE VPC-native
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

# Cloud Router + NAT agar node yang tidak punya public IP
# tetap bisa akses internet (pull image, dll.)
resource "google_compute_router" "router" {
  name    = "gke-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "gke-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Firewall: izinkan komunikasi internal antar pod/node
resource "google_compute_firewall" "internal" {
  name    = "gke-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.subnet_cidr,
    var.pods_cidr,
    var.services_cidr,
  ]
}

# =============================================================
# GKE CLUSTER — ZONAL (Jakarta: asia-southeast2-a)
# =============================================================
resource "google_container_cluster" "main" {
  name     = var.gke_cluster_name
  location = var.zone  # zonal = lebih murah dari regional

  # Hapus default node pool, ganti dengan custom node pools
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  # VPC-native cluster (wajib untuk Workload Identity & modern GKE)
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Nonaktifkan logging/monitoring untuk menekan biaya di awal
  logging_service    = "none"
  monitoring_service = "none"

  # Workload Identity (best practice keamanan)
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Maintenance window: Setiap hari pukul 00:00 - 04:00 WIB (17:00 - 21:00 UTC)
  maintenance_policy {
    daily_maintenance_window {
      start_time = "17:00"
    }
  }

  deletion_protection = false

  # Addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }
}

# =============================================================
# NODE POOL: general
# Untuk: system workloads, monitoring, ingress controller, dsb.
# Spec: e2-micro (2 vCPU / 1 GB RAM) — paling minimal
# =============================================================
resource "google_container_node_pool" "general" {
  name     = "general"
  cluster  = google_container_cluster.main.name
  location = var.zone

  initial_node_count = 1

  node_config {
    machine_type = "e2-small"
    disk_size_gb = 20
    disk_type    = "pd-standard"
    preemptible  = true  # Spot VM → hemat biaya ~80%
    image_type   = "COS_CONTAINERD"  # Container-Optimized OS

    # Label node
    labels = {
      role        = "general"
      environment = "dev"
      region      = "jakarta"
    }

    # Metadata keamanan
    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # Workload Identity di node level
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  autoscaling {
    min_node_count = 1
    max_node_count = 2
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# =============================================================
# NODE POOL: front
# Untuk: frontend workloads (web, nginx, Next.js, dsb.)
# Spec: e2-small (2 vCPU / 2 GB RAM)
# =============================================================
resource "google_container_node_pool" "front" {
  name     = "front"
  cluster  = google_container_cluster.main.name
  location = var.zone

  initial_node_count = 1

  node_config {
    machine_type = "e2-small"
    disk_size_gb = 20
    disk_type    = "pd-standard"
    preemptible  = true
    image_type   = "COS_CONTAINERD"

    labels = {
      role        = "front"
      environment = "dev"
      region      = "jakarta"
    }

    # Taint: hanya pod yang punya toleration "role=front" yang bisa masuk
    taint {
      key    = "role"
      value  = "front"
      effect = "NO_SCHEDULE"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  autoscaling {
    min_node_count = 1
    max_node_count = 2
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# =============================================================
# NODE POOL: back
# Untuk: backend workloads (API, worker, gRPC, dsb.)
# Spec: e2-small (2 vCPU / 2 GB RAM)
# =============================================================
resource "google_container_node_pool" "back" {
  name     = "back"
  cluster  = google_container_cluster.main.name
  location = var.zone

  initial_node_count = 1

  node_config {
    machine_type = "e2-small"
    disk_size_gb = 20
    disk_type    = "pd-standard"
    preemptible  = true
    image_type   = "COS_CONTAINERD"

    labels = {
      role        = "back"
      environment = "dev"
      region      = "jakarta"
    }

    taint {
      key    = "role"
      value  = "back"
      effect = "NO_SCHEDULE"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  autoscaling {
    min_node_count = 1
    max_node_count = 2
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

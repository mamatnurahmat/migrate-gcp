provider "google" {
  project = var.project_id
  region  = var.region
  # Menggunakan Application Default Credentials (gcloud auth application-default login)
}

# =============================================================
# DATA SOURCE — Ubuntu 22.04 LTS image terbaru
# =============================================================
data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

# =============================================================
# FIREWALL — Allow SSH (port 22) dari internet
# =============================================================
resource "google_compute_firewall" "allow_ssh" {
  name        = "${var.vm_name}-allow-ssh"
  network     = var.network
  description = "Allow SSH access to ${var.vm_name}"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Target: hanya VM dengan tag "ssh-access"
  target_tags   = ["ssh-access"]
  source_ranges = var.allowed_ssh_cidrs
}

# =============================================================
# FIREWALL — Allow ICMP (ping) untuk troubleshooting
# =============================================================
resource "google_compute_firewall" "allow_icmp" {
  name        = "${var.vm_name}-allow-icmp"
  network     = var.network
  description = "Allow ICMP ping to ${var.vm_name}"

  allow {
    protocol = "icmp"
  }

  target_tags   = ["ssh-access"]
  source_ranges = ["0.0.0.0/0"]
}

# =============================================================
# FIREWALL — Allow TCP 3000–4000 (dev server, app ports)
# =============================================================
resource "google_compute_firewall" "allow_app_ports" {
  name        = "${var.vm_name}-allow-app-ports"
  network     = var.network
  description = "Allow TCP 3000-4000 for dev/app servers on ${var.vm_name}"

  allow {
    protocol = "tcp"
    ports    = ["3000-4000"]
  }

  target_tags   = ["ssh-access"]
  source_ranges = ["0.0.0.0/0"]
}

# =============================================================
# FIREWALL — Allow k3s API Server (port 6443)
# Dibutuhkan untuk akses kubectl dari luar VM
# =============================================================
resource "google_compute_firewall" "allow_k3s_api" {
  name        = "${var.vm_name}-allow-k3s-api"
  network     = var.network
  description = "Allow k3s API server port 6443"

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  target_tags   = ["ssh-access"]
  source_ranges = ["0.0.0.0/0"]
}

# =============================================================
# FIREWALL — Allow k3s NodePort range (30000–32767)
# Dibutuhkan untuk akses Service type NodePort dari luar
# =============================================================
resource "google_compute_firewall" "allow_k3s_nodeport" {
  name        = "${var.vm_name}-allow-k3s-nodeport"
  network     = var.network
  description = "Allow k3s NodePort range 30000-32767"

  allow {
    protocol = "tcp"
    ports    = ["30000-32767"]
  }

  target_tags   = ["ssh-access"]
  source_ranges = ["0.0.0.0/0"]
}

# =============================================================
# VM INSTANCE — Ubuntu 22.04 LTS dengan Public IP
# =============================================================
resource "google_compute_instance" "ubuntu" {
  name         = var.vm_name
  machine_type = var.machine_type
  zone         = var.zone
  description  = "Ubuntu 22.04 LTS VM — Jakarta"

  # Tag firewall: VM ini akan kena rule allow-ssh
  tags = ["ssh-access"]

  # Boot disk — Ubuntu 22.04 LTS
  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = var.disk_size_gb
      type  = "pd-standard"
    }
  }

  # Network: gunakan VPC yang sudah ada
  network_interface {
    network    = var.network
    subnetwork = var.subnetwork

    # Access config WAJIB ada agar VM mendapat External/Public IP
    access_config {
      # Kosongkan untuk auto-assign Ephemeral IP
      # Isi network_tier jika mau Premium tier
      network_tier = "STANDARD"
    }
  }

  # Inject SSH public key lewat metadata
  metadata = {
    ssh-keys                = "${var.ssh_user}:${file(pathexpand(var.ssh_public_key_path))}"
    serial-port-enable      = "false"
    enable-osconfig         = "true"
  }

  # Startup script — update & install tools dasar
  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e
    apt-get update -qq
    apt-get install -y -qq curl wget git vim htop net-tools
    echo "✅ VM setup complete: $(hostname) at $(date)" >> /var/log/startup.log
  EOT

  # Service account scope minimal
  service_account {
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  # Scheduling: preemptible untuk hemat biaya (opsional)
  # Hapus blok di bawah jika ingin VM permanen (non-preemptible)
  scheduling {
    preemptible         = false   # Set true untuk Spot VM (lebih murah, tapi bisa dimatikan GCP)
    on_host_maintenance = "MIGRATE"
    automatic_restart   = true
  }

  labels = {
    environment = "dev"
    region      = "jakarta"
    managed-by  = "terraform"
  }

  allow_stopping_for_update = true
}

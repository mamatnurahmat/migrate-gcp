# ─────────────────────────────────────────────────────────────
# VM Configuration — Jakarta Region
# ─────────────────────────────────────────────────────────────
project_id          = "project-065701e7-213d-458b-a83"
region              = "asia-southeast2"
zone                = "asia-southeast2-a"

# VM
vm_name             = "ubuntu-vm"
machine_type        = "e2-small"   # 2 vCPU / 2 GB RAM
disk_size_gb        = 20

# SSH
# Ganti dengan path ke public key kamu
ssh_user            = "ubuntu"
ssh_public_key_path = "~/.ssh/id_rsa.pub"

# Reuse VPC yang sudah ada dari GKE setup
network             = "gke-vpc"
subnetwork          = "gke-subnet"

# Batasi SSH hanya dari IP tertentu jika mau lebih aman
# allowed_ssh_cidrs = ["203.0.113.0/24"]  # ganti dengan IP publik kamu
allowed_ssh_cidrs   = ["0.0.0.0/0"]       # allow semua (dev/testing)

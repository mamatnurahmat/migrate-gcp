variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "asia-southeast2"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "asia-southeast2-a"
}

variable "vm_name" {
  description = "Nama VM instance"
  type        = string
  default     = "ubuntu-vm"
}

variable "machine_type" {
  description = "Machine type GCP"
  type        = string
  default     = "e2-small"
}

variable "disk_size_gb" {
  description = "Ukuran boot disk (GB)"
  type        = number
  default     = 20
}

variable "ssh_user" {
  description = "Username untuk SSH"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key_path" {
  description = "Path ke public key SSH (contoh: ~/.ssh/id_rsa.pub)"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR yang diizinkan SSH. Default: semua (0.0.0.0/0)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "network" {
  description = "VPC network name (gunakan 'gke-vpc' untuk reuse existing)"
  type        = string
  default     = "gke-vpc"
}

variable "subnetwork" {
  description = "Subnet name"
  type        = string
  default     = "gke-subnet"
}

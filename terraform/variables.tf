variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region (Jakarta)"
  type        = string
  default     = "asia-southeast2"
}

variable "zone" {
  description = "GCP zone (Jakarta)"
  type        = string
  default     = "asia-southeast2-a"
}

variable "gke_cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "gke-main"
}

variable "vpc_name" {
  description = "VPC network name"
  type        = string
  default     = "gke-vpc"
}

variable "subnet_name" {
  description = "Subnet name"
  type        = string
  default     = "gke-subnet"
}

variable "subnet_cidr" {
  description = "Primary subnet CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "pods_cidr" {
  description = "Secondary CIDR for pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "Secondary CIDR for services"
  type        = string
  default     = "10.2.0.0/16"
}

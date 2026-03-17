output "vm_name" {
  description = "Nama VM"
  value       = google_compute_instance.ubuntu.name
}

output "external_ip" {
  description = "Public IP address untuk SSH"
  value       = google_compute_instance.ubuntu.network_interface[0].access_config[0].nat_ip
}

output "internal_ip" {
  description = "Internal IP address"
  value       = google_compute_instance.ubuntu.network_interface[0].network_ip
}

output "ssh_command" {
  description = "Perintah SSH siap pakai"
  value       = "ssh ${var.ssh_user}@${google_compute_instance.ubuntu.network_interface[0].access_config[0].nat_ip}"
}

output "zone" {
  description = "Zone VM berjalan"
  value       = google_compute_instance.ubuntu.zone
}

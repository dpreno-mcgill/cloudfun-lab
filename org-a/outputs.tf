# Output the relevant IP addresses for each created instance for ease of testing

output "vm_aa1_internal_ip" {
    value = google_compute_instance.vm_instance_aa1.network_interface.0.network_ip
}

output "vm_ab1_internal_ip" {
    value = google_compute_instance.vm_instance_ab1.network_interface.0.network_ip
}

output "vm_ab1_public_ip" {
    value = google_compute_instance.vm_instance_ab1.network_interface.0.access_config.0.nat_ip
}

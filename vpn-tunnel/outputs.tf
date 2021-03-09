# Output the relevant IP addresses for each created instance for ease of testing

#output "vm_aa1_internal_ip" {
#    value = google_compute_instance.vm_instance_aa1.network_interface.0.network_ip
#}

#output "vm_ab1_public_ip" {
#    value = google_compute_instance.vm_instance_ab1.network_interface.0.access_config.0.nat_ip
#}

# debugging data sources
#output "data_google_compute_network" {
#  value = data.google_compute_network.vpc-a
#}

#output "data_google_compute_network_id" {
#  value = data.google_compute_network.vpc-a.id
#}
# outputs
# data_google_compute_network_id = "projects/org-a-306519/global/networks/vpc-a"
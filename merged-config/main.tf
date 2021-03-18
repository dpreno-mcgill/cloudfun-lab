terraform {

########################################################################################################
#
# Import the Terraform provider for GCP
#
########################################################################################################

  required_providers {
    google = {
      source = "hashicorp/google"
      version = "3.5.0"
    }
  }
}

########################################################################################################
#
# Set up the Terraform providers for GCP
# We will use aliases to be able to refer to 2 different projects using 2 different credentials
#
########################################################################################################

provider "google" {
  alias = "proja"
  credentials = file(var.credentials_file_a)
  project = var.project_a
  region = var.region
  zone = var.zone
}

provider "google" {
  alias = "projb"
  credentials = file(var.credentials_file_b)
  project = var.project_b
  region = var.region
  zone = var.zone
}

########################################################################################################
#
# Create vpc network
# 2 distinct VPCs in 2 different Projects, in the same region and zone as per req 2.1
#
########################################################################################################

resource "google_compute_network" "vpc_network_a" {
  provider = google.proja
  name = "vpc-a"
  auto_create_subnetworks = false
}

resource "google_compute_network" "vpc_network_b" {
  provider = google.projb
  name = "vpc-b"
  auto_create_subnetworks = false
}

########################################################################################################
#
# Create subnets
# 4 subnets with distinct IP ranges as per req 3.1
#
########################################################################################################

resource "google_compute_subnetwork" "subnetwork_aa" {
  provider = google.proja
  name = "network-aa"
  network = google_compute_network.vpc_network_a.id
  ip_cidr_range = var.cidr_aa
}

resource "google_compute_subnetwork" "subnetwork_ab" {
  provider = google.proja
  name = "network-ab"
  network = google_compute_network.vpc_network_a.id
  ip_cidr_range = var.cidr_ab
}

resource "google_compute_subnetwork" "subnetwork_ba" {
  provider = google.projb
  name = "network-ba"
  network = google_compute_network.vpc_network_b.id
  ip_cidr_range = var.cidr_ba
}

resource "google_compute_subnetwork" "subnetwork_bb" {
  provider = google.projb
  name = "network-bb"
  network = google_compute_network.vpc_network_b.id
  ip_cidr_range = var.cidr_bb
}

########################################################################################################
#
# Compute resources
# 4 Linux VMs of type f1.micro, each in a distinct subnet as per req 2.2
# 2 of the VMs will have public ephemeral IPs as per req 4.4
# Public-facing VMs will run the startup script which installs and configures a web server as per req 4.4 and 4.5
#
########################################################################################################

resource "google_compute_instance" "vm_instance_aa1" {
  provider = google.proja
  name         = "vm-aa1"
  machine_type = var.vm_small
  tags         = ["vm-aa1", "deny-ba1-icmp", "deny-internal-icmp", "block-ba1-icmp"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnetwork_aa.id
    }
  
}

resource "google_compute_instance" "vm_instance_ab1" {
  provider = google.proja
  name         = "vm-ab1"
  machine_type = var.vm_small
  tags         = ["vm-ab1", "allow-public-http", "allow-public-icmp", "deny-bb1-public-http", "allow-bb1-public-ssh", "deny-internal-icmp"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnetwork_ab.id
      access_config {
      }
    }

  metadata_startup_script = file("startup_script.sh")
}

resource "google_compute_instance" "vm_instance_ba1" {
  provider = google.projb
  name         = "vm-ba1"
  machine_type = var.vm_small
  tags         = ["vm-ba1", "allow-aa1-icmp", "allow-internal-icmp"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnetwork_ba.id
    }

}

resource "google_compute_instance" "vm_instance_bb1" {
  provider = google.projb
  name         = "vm-bb1"
  machine_type = var.vm_small
  tags         = ["vm-bb1", "allow-public-icmp", "deny-outbound-gdns-icmp", "allow-internal-icmp"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnetwork_bb.id
      access_config {
      }
    }
  
  metadata_startup_script = file("startup_script.sh")
}

########################################################################################################
#
# Firewall rules
# Control access between VMs and from the internet as per Req 4.1, 4.2, 4.3, 4.4, 4.5
#
########################################################################################################

resource "google_compute_firewall" "firewall_vpc_a" {
  provider = google.proja
  name = "allow-public-http-access"
  network = google_compute_network.vpc_network_a.name

  allow {
    protocol  = "tcp"
    ports     = ["80"]
  }

  target_tags = [ "allow-public-http" ]
}

resource "google_compute_firewall" "firewall_vpc_a_1" {
  provider = google.proja
  name = "allow-public-icmp-access"
  network = google_compute_network.vpc_network_a.name

  allow {
    protocol  = "icmp"
  }

  target_tags = [ "allow-public-icmp" ]
}

resource "google_compute_firewall" "firewall_vpc_a_2" {
  provider = google.proja
  name = "block-internal-icmp-access"
  network = google_compute_network.vpc_network_a.name
  priority = 1000

  deny {
    protocol  = "icmp"
  }

  target_tags = [ "deny-internal-icmp" ]
  source_ranges = [ "10.0.10.0/24", "10.0.20.0/24" ]
}

#resource "google_compute_firewall" "firewall_vpc_a_3" {
#  name = "block-ba1-icmp-access"
#  network = google_compute_network.vpc_network_a.name
#  
#  deny {
#    protocol  = "icmp"
#  }
#
#  target_tags = [ "block-ba1-icmp" ]
#  source_ranges = [ "10.1.10.0/24" ]
#}

# adding a firewall rule to make sure SSH works from GCP Console
# there is a specific range of IPs which GCP will initiate connections from when you press the 'SSH' button next to the VM,
# even though this wasn't in the requirements, I'm adding it here for ease of management/testing
resource "google_compute_firewall" "firewall_vpc_a_4" {
  provider = google.proja
  name = "allow-ssh-iap"
  network = google_compute_network.vpc_network_a.name
  
  allow {
    protocol  = "tcp"
    ports     = ["22"]
  }
  
  source_ranges = [ "35.235.240.0/20" ]
}

# and a rule to allow ICMP by default
resource "google_compute_firewall" "firewall_vpc_a_5" {
  provider = google.proja
  name = "allow-icmp-default"
  network = google_compute_network.vpc_network_a.name
  
  allow {
    protocol  = "icmp"
  }
}

resource "google_compute_firewall" "firewall_vpc_b_1" {
  provider = google.projb
  name = "allow-public-icmp-access"
  network = google_compute_network.vpc_network_b.name

  allow {
    protocol  = "icmp"
  }

  target_tags = [ "allow-public-icmp" ]
}

resource "google_compute_firewall" "firewall_vpc_b_2" {
  provider = google.projb
  name = "block-outbound-gdns-icmp-access"
  network = google_compute_network.vpc_network_b.name
  direction = "EGRESS"
  priority = 1001

  deny {
    protocol  = "icmp"
  }

  # because GCP firewall is weird, the 'target' of an egress rule is actually meant to define the source VM making the connection
  # if you put 'source_tags' here you'll get an error
  target_tags = [ "deny-outbound-gdns-icmp" ]
  destination_ranges = [ "8.8.8.8/32" ]
}

resource "google_compute_firewall" "firewall_vpc_b_3" {
  provider = google.projb
  name = "allow-aa-icmp-access"
  network = google_compute_network.vpc_network_b.name

  allow {
    protocol  = "icmp"
  }

  target_tags = [ "allow-aa1-icmp" ]
  source_ranges = [ "10.0.10.0/24" ]
}

resource "google_compute_firewall" "firewall_vpc_b_4" {
  provider = google.projb
  name = "allow-internal-icmp-access"
  network = google_compute_network.vpc_network_b.name

  allow {
    protocol  = "icmp"
  }

  target_tags = [ "allow-internal-icmp" ]
  source_ranges = [ "10.1.10.0/24", "10.1.20.0/24" ]
}

# adding one additional firewall rule to make sure SSH works from GCP Console
resource "google_compute_firewall" "firewall_vpc_b_5" {
  provider = google.projb
  name = "allow-ssh-iap"
  network = google_compute_network.vpc_network_b.name
  
  allow {
    protocol  = "tcp"
    ports     = ["22"]
  }
  
  source_ranges = [ "35.235.240.0/20" ]
}

# and one more to allow ICMP by default
resource "google_compute_firewall" "firewall_vpc_b_6" {
  provider = google.projb
  name = "allow-icmp-default"
  network = google_compute_network.vpc_network_b.name
  
  allow {
    protocol  = "icmp"
  }
}

# create firewall rule in VPC A to block connections to VM-AB1's public IP on port 80 from VM-BB1's public IP
# as per Req 4.5.1

resource "google_compute_firewall" "firewall_vpc_a_7" {
  provider = google.proja
  name = "block-bb1-to-ab1-public-http"
  network = google_compute_network.vpc_network_a.name
  
  deny {
    protocol  = "tcp"
    ports     = ["80"]
  }

  target_tags = [ "deny-bb1-public-http" ]
  source_ranges = [ google_compute_instance.vm_instance_bb1.network_interface.0.access_config.0.nat_ip ]
}

# create firewall rule in VPC A to allow connections to VM-AB1's public IP on port 22 from VM-BB1's public IP
# as per Req 4.5.3
#
resource "google_compute_firewall" "firewall_vpc_a_8" {
  provider = google.proja
  name = "allow-bb1-to-ab1-public-ssh"
  network = google_compute_network.vpc_network_a.name
  
  allow {
    protocol  = "tcp"
    ports     = ["22"]
  }

  target_tags = [ "allow-bb1-public-ssh" ]
  source_ranges = [ google_compute_instance.vm_instance_bb1.network_interface.0.access_config.0.nat_ip ]
}

# Create a firewall rule on VPC-A to ensure that ICMP from VM-BA1's private address is not allowed to hit VM-AA1's private address 
# as per req 4.1.4

resource "google_compute_firewall" "firewall_vpc_a_3" {
  provider    = google.proja
  name = "block-ba1-icmp-access"
  network = google_compute_network.vpc_network_a.name
  
  deny {
    protocol  = "icmp"
  }

  target_tags = [ "block-ba1-icmp" ]
  source_ranges = [ google_compute_instance.vm_instance_ba1.network_interface.0.network_ip ]
}

########################################################################################################
#
# IAM Role assignments
# as per Req 1.2 & the documentation at https://cloud.google.com/iam/docs/understanding-roles
#
########################################################################################################

# Unfortunately, as per Google documentation, it's not possible to assign an 'owner' from another organization via API, 
# it can only be done in the Cloud Console UI (otherwise I'd have to create an Organization just for this req)
# unfortunately this part won't be automated, and will be done ahead of time in the GCP UI console
# see: https://cloud.google.com/iam/docs/granting-changing-revoking-access#granting-gcloud-manual 
#
#resource "google_project_iam_member" "sansa_owner" {
#  project = var.project_a
#  role    = "roles/owner"
#  member  = "user:sansareed.832206@gmail.com"
#}

resource "google_project_iam_member" "proja_theon_computeadmin" {
  provider = google.proja
  project = var.project_a
  role    = "roles/compute.admin"
  member  = "user:theonfrey.636475@gmail.com"
}

resource "google_project_iam_member" "proja_jon_securityadmin" {
  provider = google.proja
  project = var.project_a
  role    = "roles/iam.securityAdmin"
  member  = "user:jonfrey.601857@gmail.com"
}

resource "google_project_iam_member" "proja_petyr_netmgmt" {
  provider = google.proja
  project = var.project_a
  role    = "roles/networkmanagement.admin"
  member  = "user:petyrmormont.422614@gmail.com"
}

resource "google_project_iam_member" "projb_theon_computeadmin" {
  provider = google.projb
  project = var.project_b
  role    = "roles/compute.admin"
  member  = "user:theonfrey.636475@gmail.com"
}

resource "google_project_iam_member" "projb_jon_securityadmin" {
  provider = google.projb
  project = var.project_b
  role    = "roles/iam.securityAdmin"
  member  = "user:jonfrey.601857@gmail.com"
}

resource "google_project_iam_member" "projb_petyr_netmgmt" {
  provider = google.projb
  project = var.project_b
  role    = "roles/networkmanagement.admin"
  member  = "user:petyrmormont.422614@gmail.com"
}

########################################################################################################
#
# VPN Gateway, Tunnel, and Routes configuration
#
########################################################################################################

# Make a random string called 'ipsec_psk' of 20 characters for the VPN setup
# This will be our pre-shared key for the IPsec VPN encryption
#
# IMPORTANT NOTE about generating the PSK this way: This is sort of OK in the lab, but in the real world this can present a risk because the PSK will end up stored in cleartext in the Terraform State file.
# I would take the following mitigations in an Enterprise situation: 
# 1) Store the state file in an encrypted, access-controlled, remote location such as a GCS bucket
# 2) Migrate all secrets (such as this PSK) to a Secrets Manager such as HashiCorp Vault, so they can't be accidentally compromised and so that access is audited.
#
# Performing either of these steps would improve security, but ideally both would be implemented.

resource "random_password" "ipsec_psk" {
  length  = 20
  special = true
  upper   = true
}

#
# Reserve a static IP address for each VPN gateway, 1 for each project/VPC
#

resource "google_compute_address" "vpc-a-gw-staticip" {
  provider = google.proja
  name = "vpc-a-gw-staticip"
}

resource "google_compute_address" "vpc-b-gw-staticip" {
  provider = google.projb
  name = "vpc-b-gw-staticip"
}

#
# Create VPN gateways, attach them to their respective VPCs
#

resource "google_compute_vpn_gateway" "vpc-a-vpn-gateway" {
  provider = google.proja
  name = "vpc-a-vpn-gateway"
  network = google_compute_network.vpc_network_a.id
}

resource "google_compute_vpn_gateway" "vpc-b-vpn-gateway" {
  provider = google.projb
  name = "vpc-b-vpn-gateway"
  network = google_compute_network.vpc_network_b.id
}

#
# Create forwarding rules to ensure that IPsec traffic gets passed in to the VPN Gateways from the edge/WAN
#

resource "google_compute_forwarding_rule" "proja_fr_esp" {
  provider    = google.proja
  name        = "fr-esp"
  ip_protocol = "ESP"
  ip_address  = google_compute_address.vpc-a-gw-staticip.address
  target      = google_compute_vpn_gateway.vpc-a-vpn-gateway.id
}

resource "google_compute_forwarding_rule" "proja_fr_udp500" {
  provider    = google.proja
  name        = "fr-udp500"
  ip_protocol = "UDP"
  port_range  = "500"
  ip_address  = google_compute_address.vpc-a-gw-staticip.address
  target      = google_compute_vpn_gateway.vpc-a-vpn-gateway.id
}

resource "google_compute_forwarding_rule" "proja_fr_udp4500" {
  provider    = google.proja
  name        = "fr-udp4500"
  ip_protocol = "UDP"
  port_range  = "4500"
  ip_address  = google_compute_address.vpc-a-gw-staticip.address
  target      = google_compute_vpn_gateway.vpc-a-vpn-gateway.id
}

resource "google_compute_forwarding_rule" "projb_fr_esp" {
  provider    = google.projb
  name        = "fr-esp"
  ip_protocol = "ESP"
  ip_address  = google_compute_address.vpc-b-gw-staticip.address
  target      = google_compute_vpn_gateway.vpc-b-vpn-gateway.id
}

resource "google_compute_forwarding_rule" "projb_fr_udp500" {
  provider    = google.projb
  name        = "fr-udp500"
  ip_protocol = "UDP"
  port_range  = "500"
  ip_address  = google_compute_address.vpc-b-gw-staticip.address
  target      = google_compute_vpn_gateway.vpc-b-vpn-gateway.id
}

resource "google_compute_forwarding_rule" "projb_fr_udp4500" {
  provider    = google.projb
  name        = "fr-udp4500"
  ip_protocol = "UDP"
  port_range  = "4500"
  ip_address  = google_compute_address.vpc-b-gw-staticip.address
  target      = google_compute_vpn_gateway.vpc-b-vpn-gateway.id
}

#
# Create each side of the VPN tunnel
# One VPN tunnel object in Project A, pointing to the WAN IP of the VPN Gateway in Project B as its "peer", and vice-versa in Project B
# Manually specify Terraform dependencies so that we don't try to create the tunnels until we have all the objects we need first!
#

resource "google_compute_vpn_tunnel" "tunnel_vpca_to_vpcb" {
  provider      = google.proja
  name          = "tunnel-vpca-to-vpcb"
  peer_ip       = google_compute_address.vpc-b-gw-staticip.address
  shared_secret = random_password.ipsec_psk.result
  local_traffic_selector = [ var.cidr_aa ]
  remote_traffic_selector = [ var.cidr_ba ]

  target_vpn_gateway = google_compute_vpn_gateway.vpc-a-vpn-gateway.id

  depends_on = [
    google_compute_forwarding_rule.proja_fr_esp,
    google_compute_forwarding_rule.proja_fr_udp500,
    google_compute_forwarding_rule.proja_fr_udp4500,
    google_compute_address.vpc-a-gw-staticip,
    google_compute_address.vpc-b-gw-staticip,
  ]
}

resource "google_compute_vpn_tunnel" "tunnel_vpcb_to_vpca" {
  provider      = google.projb
  name          = "tunnel-vpcb-to-vpca"
  peer_ip       = google_compute_address.vpc-a-gw-staticip.address
  shared_secret = random_password.ipsec_psk.result
  local_traffic_selector = [ var.cidr_ba ]
  remote_traffic_selector = [ var.cidr_aa ]

  target_vpn_gateway = google_compute_vpn_gateway.vpc-b-vpn-gateway.id

  depends_on = [
    google_compute_forwarding_rule.projb_fr_esp,
    google_compute_forwarding_rule.projb_fr_udp500,
    google_compute_forwarding_rule.projb_fr_udp4500,
    google_compute_address.vpc-a-gw-staticip,
    google_compute_address.vpc-b-gw-staticip,
  ]
}

#
# Add routes to the VPC routers so they know when to direct traffic to the VPN tunnel
#

resource "google_compute_route" "route_to_vpcb" {
  provider    = google.proja
  name        = "route-to-vpcb"
  network    = google_compute_network.vpc_network_a.name
  dest_range = var.cidr_ba
  priority   = 1000

 next_hop_vpn_tunnel = google_compute_vpn_tunnel.tunnel_vpca_to_vpcb.id
}

resource "google_compute_route" "route_to_vpca" {
  provider    = google.projb
  name        = "route-to-vpca"
  network    = google_compute_network.vpc_network_b.name
  dest_range = var.cidr_aa
  priority   = 1000

  next_hop_vpn_tunnel = google_compute_vpn_tunnel.tunnel_vpcb_to_vpca.id
}

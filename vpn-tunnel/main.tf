terraform {

#
# Import the Terraform provider for GCP
#

  required_providers {
    google = {
      source = "hashicorp/google"
      version = "3.58.0"
    }
  }
}

#
# Set up the Terraform provider for GCP Project "org-a"
#

provider "google" {
  alias = "proja"
  credentials = file(var.credentials_file_a)
  project = var.project_a
  region = var.region
  zone = var.zone
}

#
# Set up the Terraform provider for GCP Project "org-b"
#

provider "google" {
  alias = "projb"
  credentials = file(var.credentials_file_b)
  project = var.project_b
  region = var.region
  zone = var.zone
}

#
# make a random string called 'ipsec_psk' of 20 characters for the VPN setup
# 
# TO DO: should we show this in 'output' along with other info at the end?

resource "random_password" "ipsec_psk" {
  length  = 20
  special = true
  upper   = true
}

#
# Go and pull in the data for the VPC networks in each project, we're going to need to attach to them so we need to know where they are
# Org-A and Org-B environments must be deployed before you can pull in their VPC data and build the tunnel (duh)
#

data "google_compute_network" "vpc-a" {
  provider = google.proja
  name = "vpc-a"
}

data "google_compute_network" "vpc-b" {
  provider = google.projb
  name = "vpc-b"
}

#
# Go and pull in the data for VM-BA1. We will need its internal IP later, we need to add it to a 'deny' policy in VPC A's firewall so that we can block VM-BA1 > VM-AA1
# As per Req 4.1.4
#

data "google_compute_instance" "vm_instance_ba1" {
  provider = google.projb
  name = "vm-ba1"
  
}

# debugging data sources
#output "data_google_compute_network_shared_vpc" {
#  value = data.google_compute_network.vpc-a
#}


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
  network = data.google_compute_network.vpc-a.id
#  network = "vpc-a"
}

resource "google_compute_vpn_gateway" "vpc-b-vpn-gateway" {
  provider = google.projb
  name = "vpc-b-vpn-gateway"
#  network = "vpc-b"
  network = data.google_compute_network.vpc-b.id
}

#
# Create forwarding rules to ensure that IPsec traffic gets passed in from the GFE
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
# Create VPN tunnel on each side, routing traffic to the other side
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
# Add routes to the VPC routers so they know when to use the VPN tunnel
#

resource "google_compute_route" "route_to_vpcb" {
  provider    = google.proja
  name        = "route-to-vpcb"
  network    = data.google_compute_network.vpc-a.name
#  network = "vpc-a"
  dest_range = var.cidr_ba
  priority   = 1000

 next_hop_vpn_tunnel = google_compute_vpn_tunnel.tunnel_vpca_to_vpcb.id
}

resource "google_compute_route" "route_to_vpca" {
  provider    = google.projb
  name        = "route-to-vpca"
  network    = data.google_compute_network.vpc-b.name
#  network = "vpc-b"
  dest_range = var.cidr_aa
  priority   = 1000

  next_hop_vpn_tunnel = google_compute_vpn_tunnel.tunnel_vpcb_to_vpca.id
}

#
# Create a firewall rule on VPC-A to ensure that ICMP from VM-BA1's private address is not allowed to hit VM-AA1's private address
#

resource "google_compute_firewall" "firewall_vpc_a_3" {
  provider    = google.proja
  name = "block-ba1-icmp-access"
  network = data.google_compute_network.vpc-a.name
  
  deny {
    protocol  = "icmp"
  }

  target_tags = [ "block-ba1-icmp" ]
  source_ranges = [ data.google_compute_instance.vm_instance_ba1.network_interface.0.network_ip ]
}
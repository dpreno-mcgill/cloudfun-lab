terraform {

#
# Import the Terraform provider for GCP
#

  required_providers {
    google = {
      source = "hashicorp/google"
      version = "3.5.0"
    }
  }
}

#
# Set up the Terraform provider for GCP
#

provider "google" {
  credentials = file(var.credentials_file)
  project = var.project_b
  region = var.region
  zone = var.zone
}

#
# make a random string called 'ipsec_psk' of 20 characters for the VPN setup
# 
# TO DO: should we show this in 'output' along with other info at the end?

#resource "random_string" "ipsec_psk" {
#  length  = 20
#  special = true
#  upper   = true
#}

#
# Create vpc networks
# - 2 distinct VPCs in 2 different Projects, in the same region and zone as per req 2.1
#

resource "google_compute_network" "vpc_network_b" {
  project = var.project_b
  name = "vpc-b"
  auto_create_subnetworks = false
}

#
# Create subnets
# - 4 subnets with distinct IP ranges as per req 3.1
#

resource "google_compute_subnetwork" "subnetwork_ba" {
  project = var.project_b
  name = "network-ba"
  network = google_compute_network.vpc_network_b.id
  ip_cidr_range = var.cidr_ba
}

resource "google_compute_subnetwork" "subnetwork_bb" {
  project = var.project_b
  name = "network-bb"
  network = google_compute_network.vpc_network_b.id
  ip_cidr_range = var.cidr_bb
}

#
# Compute resources
# - 4 Linux VMs of type f1.micro, each in a distinct subnet as per req 2.2
# - 2 of the VMs will have public ephemeral IPs as per req 4.4
# - Each VM will run the startup script which installs and configures a web server as per req 4.4 and 4.5
#

resource "google_compute_instance" "vm_instance_ba1" {
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

#
# Firewall rules
# as per Req 4.1, 4.2, 4.3, 4.4, 4.5
#

resource "google_compute_firewall" "firewall_vpc_b_1" {
  name = "allow-public-icmp-access"
  network = google_compute_network.vpc_network_b.name

  allow {
    protocol  = "icmp"
  }

  target_tags = [ "allow-public-icmp" ]
}

resource "google_compute_firewall" "firewall_vpc_b_2" {
  name = "block-outbound-gdns-icmp-access"
  network = google_compute_network.vpc_network_b.name
  direction = "EGRESS"
  priority = 1001

  deny {
    protocol  = "icmp"
  }

  # because GCP firewall is weird, the 'target' of an egress rule is the source VM making the connection
  # if you put 'source_tags' here you'll get an error
  target_tags = [ "deny-outbound-gdns-icmp" ]
  destination_ranges = [ "8.8.8.8/32" ]
}

resource "google_compute_firewall" "firewall_vpc_b_3" {
  name = "allow-aa-icmp-access"
  network = google_compute_network.vpc_network_b.name

  allow {
    protocol  = "icmp"
  }

  target_tags = [ "allow-aa1-icmp" ]
  source_ranges = [ "10.0.10.0/24" ]
}

resource "google_compute_firewall" "firewall_vpc_b_4" {
  name = "allow-internal-icmp-access"
  network = google_compute_network.vpc_network_b.name

  allow {
    protocol  = "icmp"
  }

  target_tags = [ "allow-internal-icmp" ]
  source_ranges = [ "10.1.10.0/24", "10.1.20.0/24" ]
}

# adding one additional firewall rule to make sure SSH works by default
resource "google_compute_firewall" "firewall_vpc_b_5" {
  name = "allow-ssh-default"
  network = google_compute_network.vpc_network_b.name
  
  allow {
    protocol  = "tcp"
    ports     = ["22"]
  }
}

# and one more to allow ICMP by default
resource "google_compute_firewall" "firewall_vpc_b_6" {
  name = "allow-icmp-default"
  network = google_compute_network.vpc_network_b.name
  
  allow {
    protocol  = "icmp"
  }
}
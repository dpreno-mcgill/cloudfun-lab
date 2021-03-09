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
  project = var.project_a
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
# Create vpc network
# - 2 distinct VPCs in 2 different Projects, in the same region and zone as per req 2.1
#

resource "google_compute_network" "vpc_network_a" {
  name = "vpc-a"
  auto_create_subnetworks = false
}

#
# Create subnets
# - 4 subnets with distinct IP ranges as per req 3.1
#

resource "google_compute_subnetwork" "subnetwork_aa" {
  name = "network-aa"
  network = google_compute_network.vpc_network_a.id
  ip_cidr_range = var.cidr_aa
}

resource "google_compute_subnetwork" "subnetwork_ab" {
  name = "network-ab"
  network = google_compute_network.vpc_network_a.id
  ip_cidr_range = var.cidr_ab
}

#
# Compute resources
# - 4 Linux VMs of type f1.micro, each in a distinct subnet as per req 2.2
# - 2 of the VMs will have public ephemeral IPs as per req 4.4
# - Each VM will run the startup script which installs and configures a web server as per req 4.4 and 4.5
#

resource "google_compute_instance" "vm_instance_aa1" {
  name         = "vm-aa1"
  machine_type = var.vm_small
  tags         = ["vm-aa1", "deny-ba1-icmp", "deny-internal-icmp"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnetwork_aa.id
    }
  
  metadata_startup_script = file("startup_script.sh")
}


resource "google_compute_instance" "vm_instance_ab1" {
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

#
# Firewall rules
# as per Req 4.1, 4.2, 4.3, 4.4, 4.5
#

resource "google_compute_firewall" "firewall_vpc_a" {
  name = "allow-public-http-access"
  network = google_compute_network.vpc_network_a.name

  allow {
    protocol  = "tcp"
    ports     = ["80"]
  }

  target_tags = [ "allow-public-http" ]
}

resource "google_compute_firewall" "firewall_vpc_a_1" {
  name = "allow-public-icmp-access"
  network = google_compute_network.vpc_network_a.name

  allow {
    protocol  = "icmp"
  }

  target_tags = [ "allow-public-icmp" ]
}

resource "google_compute_firewall" "firewall_vpc_a_2" {
  name = "block-internal-icmp-access"
  network = google_compute_network.vpc_network_a.name
  priority = 1000

  deny {
    protocol  = "icmp"
  }

  target_tags = [ "deny-internal-icmp" ]
  source_ranges = [ "10.0.10.0/24", "10.0.20.0/24" ]
}

resource "google_compute_firewall" "firewall_vpc_a_3" {
  name = "block-ba1-icmp-access"
  network = google_compute_network.vpc_network_a.name
  
  deny {
    protocol  = "icmp"
  }

  target_tags = [ "block-ba1-icmp" ]
  source_ranges = [ "10.1.10.0/24" ]
}

# adding one additional firewall rule to make sure SSH works by default
resource "google_compute_firewall" "firewall_vpc_a_4" {
  name = "allow-ssh-default"
  network = google_compute_network.vpc_network_a.name
  
  allow {
    protocol  = "tcp"
    ports     = ["22"]
  }
}

# and one more to allow ICMP by default
resource "google_compute_firewall" "firewall_vpc_a_5" {
  name = "allow-icmp-default"
  network = google_compute_network.vpc_network_a.name
  
  allow {
    protocol  = "icmp"
  }
}
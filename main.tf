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
  region = var.region
  zone = var.zone
}

#
# make a random string called 'ipsec_psk' of 20 characters for the VPN setup
# 
# TO DO: should we show this in 'output' along with other info at the end?

resource "random_string" "ipsec_psk" {
  length  = 20
  special = true
  upper   = true
}

#
# Create vpc networks
# - 2 distinct VPCs in 2 different Projects, in the same region and zone as per req 2.1
#

resource "google_compute_network" "vpc_network_a" {
  project = var.project_a
  name = "vpc-a"
  auto_create_subnetworks = false
}

resource "google_compute_network" "vpc_network_b" {
  project = var.project_b
  name = "vpc-b"
  auto_create_subnetworks = false
}

#
# Create subnets
# - 4 subnets with distinct IP ranges as per req 3.1
#

resource "google_compute_subnetwork" "subnetwork_aa" {
  project = var.project_a
  name = "network-aa"
  network = google_compute_network.vpc_network_a.id
  ip_cidr_range = var.cidr_aa
}

resource "google_compute_subnetwork" "subnetwork_ab" {
  project = var.project_a
  name = "network-ab"
  network = google_compute_network.vpc_network_a.id
  ip_cidr_range = var.cidr_ab
}

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

resource "google_compute_instance" "vm_instance_aa1" {
  name         = "VM-AA1"
  machine_type = var.vm_small
  tags         = ["aa1", "dev"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }

  network_interface {
    network = google_compute_subnetwork.subnetwork_aa.id
    }
  
  metadata_startup_script = file("startup_script.sh")
}


resource "google_compute_instance" "vm_instance_ab1" {
  name         = "VM-AB1"
  machine_type = var.vm_small

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }

  network_interface {
    network = google_compute_subnetwork.subnetwork_ab.id
      access_config {
      }
    }

  metadata_startup_script = file("startup_script.sh")
}

resource "google_compute_instance" "vm_instance_ba1" {
  name         = "VM-BA1"
  machine_type = var.vm_small

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }

  network_interface {
    network = google_compute_subnetwork.subnetwork_ba.id
    }

  metadata_startup_script = file("startup_script.sh")
}

resource "google_compute_instance" "vm_instance_bb1" {
  name         = "VM-BB1"
  machine_type = var.vm_small

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }

  network_interface {
    network = google_compute_subnetwork.subnetwork_bb.id
      access_config {
      }
    }
  
  metadata_startup_script = file("startup_script.sh")
}
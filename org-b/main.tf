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

provider "google" {
  alias = "proja"
  credentials = file(var.credentials_file_a)
  project = var.project_a
  region = var.region
  zone = var.zone
}

#
# Pull in data for Org A's VPC so that we can add some firewall rules later to control access between VM-BB and VM-AB's public IPs
#

data "google_compute_network" "vpc-a" {
  provider = google.proja
  name = "vpc-a"
}

#
# Pull in data for Org A's VM-AB1 so that we can get its public IP for creating firewall policy later
#

#data "google_compute_instance" "vm_instance_ab1" {
#  provider = google.proja
#  name = "vm-ab1"
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

# adding one additional firewall rule to make sure SSH works from GCP Console
resource "google_compute_firewall" "firewall_vpc_b_5" {
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
  name = "allow-icmp-default"
  network = google_compute_network.vpc_network_b.name
  
  allow {
    protocol  = "icmp"
  }
}

# create firewall rule in VPC A to block connections to VM-AB1's public IP on port 80 from VM-BB1's public IP
# as per Req 4.5.1
#
resource "google_compute_firewall" "firewall_vpc_a_7" {
  provider = google.proja
  name = "block-bb1-to-ab1-public-http"
  network = data.google_compute_network.vpc-a.name
  
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
  network = data.google_compute_network.vpc-a.name
  
  allow {
    protocol  = "tcp"
    ports     = ["22"]
  }

  target_tags = [ "allow-bb1-public-ssh" ]
  source_ranges = [ google_compute_instance.vm_instance_bb1.network_interface.0.access_config.0.nat_ip ]
}

#
# IAM Role assignments
# as per Req 1.2 & the documentation at https://cloud.google.com/iam/docs/understanding-roles
#

resource "google_project_iam_member" "sansa_owner" {
  project = var.project_b
  role    = "roles/owner"
  member  = "user:sansareed.832206@gmail.com"
}

resource "google_project_iam_member" "theon_computeadmin" {
  project = var.project_b
  role    = "roles/compute.admin"
  member  = "user:theonfrey.636475@gmail.com"
}

resource "google_project_iam_member" "jon_securityadmin" {
  project = var.project_b
  role    = "roles/iam.securityAdmin"
  member  = "user:jonfrey.601857@gmail.com"
}

resource "google_project_iam_member" "petyr_netmgmt" {
  project = var.project_b
  role    = "roles/networkmanagement.admin"
  member  = "user:petyrmormont.422614@gmail.com"
}
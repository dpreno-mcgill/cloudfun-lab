# Following Terraform best practices, this file serves to instantiate the variables which I chose to use in my scripts
# I decided to leave them all empty (no default values) to make sure that the tfvars file would be the clear authority in controlling the env

# defining the variable for the connection provider

variable "credentials_file" {}

# defining the variables for projects

variable "project_a" {}

# defining the variables for regions and zones

variable "region" {}
variable "zone" {}

# network cidrs

variable "cidr_aa" {}
variable "cidr_ab" {}

# machine type

variable "vm_small" {}

#
# maps - lookup tables to specify different types of machines based on the purpose of the machine dev/test/prod
#

#variable "environment" {
#  type    = string
#  default = "dev"
#}
#
#variable "machine_types" {
#  type    = map
#  default = {
#    dev  = "f1-micro"
#    prod = "n1-highcpu-32"
#  }
#}

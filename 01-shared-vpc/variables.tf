variable "host_project_id" {
  description = "Project ID that owns the Shared VPC network."
  type        = string
}

variable "service_project_id" {
  description = "Project ID that will host the OSD cluster as a Shared VPC service project."
  type        = string
}

variable "region" {
  description = "GCP region for the VPC and subnets."
  type        = string
  default     = "us-east1"
}

variable "network_name" {
  description = "Name of the Shared VPC network in the host project."
  type        = string
  default     = "osd-shared-vpc"
}

# CIDR plan
# - control plane: small, just enough for master nodes
# - compute:       worker nodes
# - psc:           dedicated /29 for Private Service Connect service attachment
variable "control_plane_cidr" {
  type    = string
  default = "10.0.0.0/28"
}

variable "compute_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "psc_cidr" {
  type    = string
  default = "10.0.2.0/29"
}

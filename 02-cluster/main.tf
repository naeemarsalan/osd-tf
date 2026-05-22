###############################################################################
# Phase 2: OSD-GCP cluster composing WIF + CMEK + PSC + Shared VPC + private API
###############################################################################
#
# Consumes Phase 1's shared-VPC outputs via terraform_remote_state. Phase 1
# lives at ../01-shared-vpc and is applied with a local backend.
#
# Apply order (Terraform graph handles this automatically):
#   1. osdgoogle_wif_config in OCM             (wif.tf)
#   2. WIF GCP IAM (workload identity pool + SAs + role bindings)
#   3. KMS keyring + key + dedicated SA + IAM  (kms.tf)
#   4. osdgoogle_cluster                       (cluster.tf)
#   5. osdgoogle_identity_provider (htpasswd)  (idp.tf)
###############################################################################

data "terraform_remote_state" "shared_vpc" {
  backend = "local"
  config = {
    path = "../01-shared-vpc/terraform.tfstate"
  }
}

data "google_project" "service" {
  project_id = local.service_project_id
}

locals {
  host_project_id      = data.terraform_remote_state.shared_vpc.outputs.host_project_id
  service_project_id   = data.terraform_remote_state.shared_vpc.outputs.service_project_id
  region               = data.terraform_remote_state.shared_vpc.outputs.region
  network_name         = data.terraform_remote_state.shared_vpc.outputs.network_name
  control_plane_subnet = data.terraform_remote_state.shared_vpc.outputs.control_plane_subnet
  compute_subnet       = data.terraform_remote_state.shared_vpc.outputs.compute_subnet
  psc_subnet           = data.terraform_remote_state.shared_vpc.outputs.psc_subnet

  openshift_version = var.openshift_version
}

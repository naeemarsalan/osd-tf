###############################################################################
# Host-project IAM grants for OSD shared-VPC cluster SAs
###############################################################################
# OSD validates that the cluster's service accounts (created by WIF GCP IAM)
# have Compute Network Admin + Compute Security Admin + DNS Administrator on
# the Shared VPC host project. Without these the cluster sits in `waiting`
# with "Could not validate the shared subnets".

locals {
  host_iam_principals = [
    "serviceAccount:osd-deployer-upba@${local.service_project_id}.iam.gserviceaccount.com",
    "serviceAccount:osd-control-plane-upba@${local.service_project_id}.iam.gserviceaccount.com",
    "serviceAccount:machine-api-gcp-upba@${local.service_project_id}.iam.gserviceaccount.com",
  ]
  host_iam_roles = [
    "roles/compute.networkAdmin",
    "roles/compute.securityAdmin",
    "roles/dns.admin",
  ]
  host_iam_bindings = {
    for pair in setproduct(local.host_iam_principals, local.host_iam_roles) :
    "${pair[0]}-${pair[1]}" => { member = pair[0], role = pair[1] }
  }
}

resource "google_project_iam_member" "host" {
  for_each = local.host_iam_bindings

  project = local.host_project_id
  role    = each.value.role
  member  = each.value.member

  depends_on = [module.wif_gcp]
}

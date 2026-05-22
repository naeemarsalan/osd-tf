###############################################################################
# OSD cluster: WIF + CMEK + Shared VPC + PSC + private API
###############################################################################
# Trial product (osdtrial) — 60-day evaluation, no OSD service fee.
# GCP infra costs (VMs, disks, NAT, KMS) still apply.

resource "osdgoogle_cluster" "osd" {
  depends_on = [
    module.wif_gcp,
    google_kms_crypto_key_iam_member.kms_sa,
    google_kms_crypto_key_iam_member.compute_agent,
  ]

  name           = var.cluster_name
  product        = "osdtrial"
  cloud_region   = local.region
  gcp_project_id = local.service_project_id
  wif_config_id  = osdgoogle_wif_config.wif.id
  version        = local.openshift_version
  compute_nodes  = var.compute_nodes
  ccs_enabled    = true
  private        = true

  gcp_network = {
    vpc_name             = local.network_name
    vpc_project_id       = local.host_project_id
    compute_subnet       = local.compute_subnet
    control_plane_subnet = local.control_plane_subnet
  }

  private_service_connect = {
    service_attachment_subnet = local.psc_subnet
  }

  gcp_encryption_key = {
    kms_key_service_account = google_service_account.kms.email
    key_location            = local.region
    key_name                = google_kms_crypto_key.osd.name
    key_ring                = google_kms_key_ring.osd.name
  }

  security = {
    secure_boot = true
  }
}

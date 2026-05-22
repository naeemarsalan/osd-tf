###############################################################################
# WIF: OCM config + GCP-side IAM
###############################################################################
# osdgoogle_wif_config registers the federation in OCM and returns the GCP
# workload-identity-pool blueprint. osd-wif-gcp then creates the actual pool,
# OIDC provider, service accounts, and role bindings in GCP.
#
# Resource (not module) so the full `gcp` blueprint is referenceable in this
# stack without a chicken-and-egg data source.

resource "osdgoogle_wif_config" "wif" {
  display_name      = "${var.cluster_name}-wif"
  openshift_version = local.openshift_version
  gcp = {
    project_id     = local.service_project_id
    project_number = tostring(data.google_project.service.number)
    role_prefix    = replace(replace(var.cluster_name, "-", ""), "_", "")
  }
}

module "wif_gcp" {
  source = "../provider-extension/terraform-provider-osd-google/modules/osd-wif-gcp"

  project_id   = local.service_project_id
  display_name = osdgoogle_wif_config.wif.display_name
  pool_id      = osdgoogle_wif_config.wif.gcp.workload_identity_pool.pool_id
  identity_provider = {
    identity_provider_id = osdgoogle_wif_config.wif.gcp.workload_identity_pool.identity_provider.identity_provider_id
    issuer_url           = osdgoogle_wif_config.wif.gcp.workload_identity_pool.identity_provider.issuer_url
    jwks                 = osdgoogle_wif_config.wif.gcp.workload_identity_pool.identity_provider.jwks
    allowed_audiences    = osdgoogle_wif_config.wif.gcp.workload_identity_pool.identity_provider.allowed_audiences
  }
  service_accounts         = osdgoogle_wif_config.wif.gcp.service_accounts
  support                  = osdgoogle_wif_config.wif.gcp.support
  impersonator_email       = osdgoogle_wif_config.wif.gcp.impersonator_email
  federated_project_id     = try(osdgoogle_wif_config.wif.gcp.federated_project_id, "") != "" ? osdgoogle_wif_config.wif.gcp.federated_project_id : null
  federated_project_number = try(osdgoogle_wif_config.wif.gcp.federated_project_number, "") != "" ? osdgoogle_wif_config.wif.gcp.federated_project_number : tostring(data.google_project.service.number)
}

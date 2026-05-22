###############################################################################
# Identity provider: htpasswd with single admin user
###############################################################################
# Uses the osdgoogle_identity_provider resource added on the
# feat/osdgoogle-identity-provider branch of the MOBB provider.
# The OCM IdP API is cluster-type-agnostic; htpasswd is the simplest way to
# get an interactive `oc login` working on a fresh cluster.

resource "osdgoogle_identity_provider" "htpasswd" {
  cluster        = osdgoogle_cluster.osd.id
  name           = "htpasswd"
  mapping_method = "claim"
  htpasswd = {
    users = [
      {
        username = "admin"
        password = var.admin_password
      },
    ]
  }
}

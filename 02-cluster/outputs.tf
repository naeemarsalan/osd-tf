output "cluster_id" {
  value       = osdgoogle_cluster.osd.id
  description = "OCM cluster ID"
}

output "cluster_name" {
  value       = osdgoogle_cluster.osd.name
  description = "OSD cluster name"
}

output "api_url" {
  value       = osdgoogle_cluster.osd.api_url
  description = "Kubernetes API endpoint (private PSC URL)"
}

output "console_url" {
  value       = osdgoogle_cluster.osd.console_url
  description = "OpenShift console URL"
}

output "wif_config_id" {
  value       = osdgoogle_wif_config.wif.id
  description = "OCM WIF config ID consumed by the cluster"
}

output "kms_key_self_link" {
  value       = google_kms_crypto_key.osd.id
  description = "CMEK key resource path"
}

output "bastion_ssh_command" {
  value       = "gcloud compute ssh ${google_compute_instance.bastion.name} --zone=${google_compute_instance.bastion.zone} --project=${local.service_project_id} --tunnel-through-iap"
  description = "Reach the bastion via IAP. From there, `oc login` against the private cluster API."
}

output "idp_login_command" {
  value       = "oc login --username=admin --password='<see /tmp/osd-poc-admin-password.txt>' ${osdgoogle_cluster.osd.api_url}"
  description = "Run this from the bastion after `gcloud compute ssh` to authenticate via the htpasswd IdP."
}

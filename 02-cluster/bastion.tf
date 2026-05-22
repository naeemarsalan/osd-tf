###############################################################################
# Bastion VM for reaching the private cluster API via IAP SSH tunneling
###############################################################################
# The cluster's API is PSC-private; this bastion provides the only on-VPC
# foothold from which `oc login` works.
#
# Pattern (from MOBB examples/cluster_private): CentOS Stream 9, no external IP,
# OS Login enabled, reached via `gcloud compute ssh --tunnel-through-iap`.
# Sits in the existing shared-VPC compute subnet so it inherits the worker
# subnet's NAT and firewall rules.

# IAP source range is static and documented:
# https://cloud.google.com/iap/docs/using-tcp-forwarding
resource "google_compute_firewall" "iap_ssh" {
  project = local.host_project_id
  name    = "${var.cluster_name}-iap-ssh"
  network = local.network_name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["iap-ssh"]
}

data "google_compute_image" "centos" {
  family  = "centos-stream-9"
  project = "centos-cloud"
}

resource "google_compute_instance" "bastion" {
  project      = local.service_project_id
  name         = "${var.cluster_name}-bastion"
  machine_type = "e2-small"
  zone         = "${local.region}-b"

  tags = ["iap-ssh"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.centos.self_link
      size  = 20
      type  = "pd-standard"
    }
  }

  network_interface {
    # Shared VPC: reference the host-project subnet by full self-link.
    subnetwork         = "projects/${local.host_project_id}/regions/${local.region}/subnetworks/${local.compute_subnet}"
    subnetwork_project = local.host_project_id
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -euo pipefail
    OC_MIRROR="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable"
    curl -sL "$${OC_MIRROR}/openshift-client-linux.tar.gz" \
      | tar -xz -C /usr/local/bin oc kubectl
    chmod +x /usr/local/bin/oc /usr/local/bin/kubectl
  EOT

  shielded_instance_config {
    enable_secure_boot = true
  }
}

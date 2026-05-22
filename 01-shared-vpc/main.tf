###############################################################################
# Service enablement
###############################################################################

resource "google_project_service" "host_compute" {
  project            = var.host_project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "svc_compute" {
  project            = var.service_project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

###############################################################################
# Shared VPC: host enable + service project attach
###############################################################################

resource "google_compute_shared_vpc_host_project" "host" {
  project    = var.host_project_id
  depends_on = [google_project_service.host_compute]
}

resource "google_compute_shared_vpc_service_project" "svc" {
  host_project    = google_compute_shared_vpc_host_project.host.project
  service_project = var.service_project_id

  depends_on = [google_project_service.svc_compute]
}

###############################################################################
# Shared VPC network and subnets (in host project)
###############################################################################

resource "google_compute_network" "shared" {
  project                 = var.host_project_id
  name                    = var.network_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_compute_shared_vpc_host_project.host]
}

resource "google_compute_subnetwork" "control_plane" {
  project                  = var.host_project_id
  name                     = "${var.network_name}-cp"
  region                   = var.region
  network                  = google_compute_network.shared.id
  ip_cidr_range            = var.control_plane_cidr
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "compute" {
  project                  = var.host_project_id
  name                     = "${var.network_name}-compute"
  region                   = var.region
  network                  = google_compute_network.shared.id
  ip_cidr_range            = var.compute_cidr
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "psc" {
  project       = var.host_project_id
  name          = "${var.network_name}-psc"
  region        = var.region
  network       = google_compute_network.shared.id
  ip_cidr_range = var.psc_cidr
  purpose       = "PRIVATE_SERVICE_CONNECT"
}

###############################################################################
# Cloud NAT so the private cluster can reach the public internet for pulls
###############################################################################

resource "google_compute_router" "nat" {
  project = var.host_project_id
  name    = "${var.network_name}-router"
  region  = var.region
  network = google_compute_network.shared.id
}

resource "google_compute_router_nat" "nat" {
  project                            = var.host_project_id
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.nat.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

###############################################################################
# Firewall: allow intra-VPC traffic
###############################################################################

resource "google_compute_firewall" "internal" {
  project = var.host_project_id
  name    = "${var.network_name}-allow-internal"
  network = google_compute_network.shared.name

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.control_plane_cidr,
    var.compute_cidr,
    var.psc_cidr,
  ]
}

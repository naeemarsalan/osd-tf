output "host_project_id" {
  value = google_compute_shared_vpc_host_project.host.project
}

output "service_project_id" {
  value = google_compute_shared_vpc_service_project.svc.service_project
}

output "network_name" {
  value = google_compute_network.shared.name
}

output "network_self_link" {
  value = google_compute_network.shared.self_link
}

output "control_plane_subnet" {
  value = google_compute_subnetwork.control_plane.name
}

output "compute_subnet" {
  value = google_compute_subnetwork.compute.name
}

output "psc_subnet" {
  value = google_compute_subnetwork.psc.name
}

output "region" {
  value = var.region
}

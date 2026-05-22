variable "cluster_name" {
  type        = string
  default     = "osd-poc"
  description = "Cluster name; also used to derive WIF display name and KMS key/SA names."
}

variable "openshift_version" {
  type        = string
  default     = "4.21.15"
  description = "OSD version. Must be >= 4.17 for WIF support."
}

variable "compute_nodes" {
  type        = number
  default     = 3
  description = "Worker node count. Trial quota caps the cluster at 40 worker vCPUs."
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Password for the htpasswd `admin` identity provider user. Set via TF_VAR_admin_password."
}

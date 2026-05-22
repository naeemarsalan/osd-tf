terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    osdgoogle = {
      source = "rh-mobb/osd-google"
    }
  }
}

provider "google" {
  region = local.region
}

# OCM token is read from OSDGOOGLE_TOKEN environment variable.
# Run: export OSDGOOGLE_TOKEN=$(ocm token)
provider "osdgoogle" {
  openshift_version = local.openshift_version
}

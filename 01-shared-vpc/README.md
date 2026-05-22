# Phase 1 — Shared VPC + networking

Builds the host VPC, subnets, Cloud NAT, and Shared-VPC host/service link
between the host project (you own the VPC there) and the service project
(the OSD cluster runs there).

Phase 2 (`../02-cluster/`) layers KMS, WIF config, and the OSD cluster on
top of this.

## Prereqs

- A GCP organization (Shared VPC requires one — personal "no org" GCP
  accounts cannot use Shared VPC).
- Two projects already created and billed: one host, one service.
- gcloud authenticated as an account with **Org Admin** and **Shared VPC
  Admin** on the org:

  ```
  gcloud auth application-default login
  gcloud auth application-default set-quota-project <host-project-id>
  ```

## Apply

```
cd 01-shared-vpc
terraform init
terraform apply \
  -var=host_project_id=<host-project-id> \
  -var=service_project_id=<service-project-id>
```

(or copy `terraform.tfvars.example` to `terraform.tfvars` and edit.)

## What it produces

- Compute API enabled on both projects
- Host project enabled as Shared VPC host
- Service project attached as service project
- VPC `osd-shared-vpc` with three subnets:
  - `osd-shared-vpc-cp`      (control plane, /28)
  - `osd-shared-vpc-compute` (workers, /24)
  - `osd-shared-vpc-psc`     (PSC service attachment, /29)
- Cloud Router + Cloud NAT for egress
- Internal-allow firewall

## Verify

```
gcloud compute shared-vpc get-host-project <service-project-id>
# expect: hostProject = <host-project-id>

gcloud compute networks subnets list \
  --project=<host-project-id> --filter="network:osd-shared-vpc"
```

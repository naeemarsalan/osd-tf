# OSD-on-GCP PoC workspace

## What this is

Proof-of-concept Terraform for running OpenShift Dedicated (OSD) on Google
Cloud Platform with four advanced features composed on a single cluster:

1. **WIF** — Workload Identity Federation (no long-lived service account keys)
2. **CMEK** — Customer-managed encryption keys (etcd, disks)
3. **PSC** — Private Service Connect (private cluster endpoint)
4. **Shared VPC** — Two-project network topology (host owns the VPC, service runs the cluster)

Plus a custom `osdgoogle_identity_provider` resource added to
`rh-mobb/terraform-provider-osd-google` so an htpasswd IdP can be managed
in the same stack.

## Layout

```
osd-tf/
├── 01-shared-vpc/   # Phase 1: Shared VPC infra (host + service projects,
│                    #          VPC, subnets, NAT)
└── 02-cluster/      # Phase 2: WIF + KMS + cluster + IdP + bastion
```

The provider lives in a separate repo (a fork of
`rh-mobb/terraform-provider-osd-google` with the `identity_provider`
resource added). See `README.md` step 3 for how to wire it via
`dev_overrides`.

## How to use

`README.md` is the build runbook — read top to bottom. It covers:

- One-time GCP prereqs (org-policy admin role, API enablement, quota
  increases, `iam.allowedPolicyMemberDomains` relaxation)
- Phase 1 apply (Shared VPC)
- Phase 2 apply (cluster + everything else)
- Verification (`02-cluster/verify.sh`)
- Destroy + rebuild

Every pitfall called out in the runbook was hit during the original
build — don't skip the prereqs.

## What an agent picking this up should do first

1. Read `README.md` end to end.
2. Run `gcloud organizations list && gcloud auth list && ocm whoami` to
   confirm authentication state matches the assumptions in section 0.
3. Run `gcloud services list --enabled --project=<service-project>` and
   compare against the API list in section 1.3. Anything missing → enable
   before applying.

## What an agent should NOT do

- Don't paste tokens, client secrets, or `ocm token` output into chat.
- Don't commit `.env.local`, `terraform.tfstate`, `tfplan`, or
  `*.tfvars` (gitignored — keep it that way).
- Don't `gcloud projects delete` anything — GCP project IDs are unique
  within an org and recovery requires re-creation.
- Don't change the active gcloud / ocm identity without explicit ask;
  Phase 1 state binds to specific account credentials.
- Don't widen `iam.allowedPolicyMemberDomains` org-wide unless the user
  explicitly approves — the project-level `allowAll` override on the
  service project alone is the minimum-blast-radius path.

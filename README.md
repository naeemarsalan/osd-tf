# OSD-on-GCP PoC: WIF + CMEK + PSC + Shared VPC — Step-by-Step Runbook

Build instruction for a single OSD-on-GCP cluster that composes four
advanced features at once:

1. **WIF** — Workload Identity Federation (no long-lived service account keys)
2. **CMEK** — Customer-managed encryption keys (etcd + worker disks)
3. **PSC** — Private Service Connect (cluster API endpoint is internal-only)
4. **Shared VPC** — Two-project network topology (host owns the VPC, service runs the cluster)

Plus a `htpasswd` identity provider so a human can `oc login` once the
cluster is up, reached over PSC via an IAP-tunneled bastion.

Follow top-to-bottom for a clean build. **Every pitfall in this doc was
hit during the original run** — don't skip the prereqs.

---

## 0. Prereq state assumed by this runbook

| | |
|---|---|
| GCP organization | a real Cloud Identity / Workspace org (Shared VPC needs one — personal "no-org" GCP cannot use Shared VPC) |
| GCP host project | the project that owns the Shared VPC |
| GCP service project | the project that runs the OSD cluster |
| Billing account | linked to both projects |
| Active gcloud account | Org Admin + Shared VPC Admin on the org |
| OCM account | a Red Hat account with OSD-GCP quota in your OCM org |
| Region | `us-east1` (other regions work; update Phase 1 vars) |
| OSD version | `4.21.15` (must be `>=4.17` for WIF) |
| Cluster name | `osd-poc` (kept short — derived names hit GCP SA email length limits) |

Throughout this doc, `<HOST_PROJECT>`, `<SERVICE_PROJECT>`, `<GCP_ORG_ID>`,
`<GCP_ADMIN_USER>`, etc., are placeholders for your values. Set them in
shell vars to make the snippets copy-pasteable:

```bash
export HOST_PROJECT=<your-host-project-id>
export SERVICE_PROJECT=<your-service-project-id>
export GCP_ORG_ID=<your-gcp-org-id>
export GCP_ADMIN_USER=<your-gcp-admin@your-domain>
```

---

## 1. One-time GCP prerequisites (org-level)

These can't live in Terraform — they touch IAM at the organization or
require API enablement before TF can run. Run as the org admin.

### 1.1 Grant yourself `orgpolicy.policyAdmin`

`resourcemanager.organizationAdmin` does NOT include
`orgpolicy.policies.update`. Without this you cannot modify the org policy
in step 1.4.

```bash
gcloud organizations add-iam-policy-binding "$GCP_ORG_ID" \
  --member="user:$GCP_ADMIN_USER" \
  --role=roles/orgpolicy.policyAdmin \
  --condition=None
```

### 1.2 Request GCP quota increases on the service project

**This is the biggest pitfall.** Default GCP project quotas are far below
what an OSD cluster needs, and the failure mode is misleading: the install
log shows "must provide bootstrap host address" / "failed to provision
control-plane machines within 15m0s", which looks like a networking issue
but is actually GCP refusing to create VMs.

Bare-minimum OSD cluster (3 masters + 2 infra + 3 compute + 1 bootstrap at
peak) requires roughly:

| Quota | Service | Default | Required (minimum) |
|---|---|---|---|
| `CPUS_ALL_REGIONS` (global) | compute.googleapis.com | 32 | **48+** |
| `SSD_TOTAL_GB` per region | compute.googleapis.com | 500 | **1500+** |
| `IN_USE_ADDRESSES` per region | compute.googleapis.com | 8 | **16+** |
| `CPUS` per region | compute.googleapis.com | 24 | **48+** |

Verify current state:

```bash
gcloud compute regions describe us-east1 --project="$SERVICE_PROJECT" \
  --format='value(quotas)' | tr ',' '\n' | grep -iE "cpus|ssd|address"
gcloud compute project-info describe --project="$SERVICE_PROJECT" \
  --format='value(quotas)' | tr ',' '\n' | grep -iE "cpus_all|networks"
```

Request increases via the console
(<https://console.cloud.google.com/iam-admin/quotas> — filter and "EDIT
QUOTAS") **or programmatically** via the Cloud Quotas alpha API:

```bash
gcloud services enable cloudquotas.googleapis.com --project="$SERVICE_PROJECT"

# CPUs (all regions) → 48
gcloud alpha quotas preferences create \
  --service=compute.googleapis.com --project="$SERVICE_PROJECT" \
  --quota-id=CPUS-ALL-REGIONS-per-project \
  --preferred-value=48 \
  --email="$GCP_ADMIN_USER" \
  --justification="OSD-on-GCP cluster (3 masters + 2 infra + 3 compute + 1 bootstrap at install peak = 36 vCPU)" \
  --preference-id=osd-poc-cpus-all-regions

# Persistent Disk SSD in us-east1 → 2000
gcloud alpha quotas preferences create \
  --service=compute.googleapis.com --project="$SERVICE_PROJECT" \
  --quota-id=SSD-TOTAL-GB-per-project-region \
  --preferred-value=2000 \
  --dimensions=region=us-east1 \
  --email="$GCP_ADMIN_USER" \
  --justification="OSD-on-GCP cluster: 8 nodes x 128 GB SSD + bootstrap = ~1100 GB; 2000 for headroom" \
  --preference-id=osd-poc-ssd-us-east1
```

Confirm approval (look for `grantedValue` matching `preferredValue`):

```bash
gcloud alpha quotas preferences describe osd-poc-cpus-all-regions \
  --project="$SERVICE_PROJECT"
gcloud alpha quotas preferences describe osd-poc-ssd-us-east1 \
  --project="$SERVICE_PROJECT"
```

Approval is automatic for first-tier increases (typically under
~30 minutes) but can take days for higher tiers. The first attempt at
`32 → 64` for CPUs was denied automatically; `32 → 48` was approved.
Start with smaller increases if you hit denials. **Don't start a cluster
apply until both `grantedValue`s match.**

**Symptom if you skip this:** cluster goes into `error` state ~30 min into
install with `Details: UnknownError`. Confirm with:

```bash
gcloud compute operations list --project="$SERVICE_PROJECT" \
  --filter="targetLink~<cluster-name> AND status=DONE AND error.errors[0].code=QUOTA_EXCEEDED" \
  --format='value(operationType,error.errors[0].message)' | head
```

### 1.3 Enable APIs on both projects

```bash
# Service project: everything OSD needs
gcloud services enable \
  compute.googleapis.com \
  cloudkms.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  dns.googleapis.com \
  cloudresourcemanager.googleapis.com \
  deploymentmanager.googleapis.com \
  networksecurity.googleapis.com \
  iap.googleapis.com \
  orgpolicy.googleapis.com \
  serviceusage.googleapis.com \
  --project="$SERVICE_PROJECT"

# Host project: just enough for shared VPC + org-policy inspection
gcloud services enable \
  compute.googleapis.com \
  orgpolicy.googleapis.com \
  --project="$HOST_PROJECT"
```

**Pitfall**: missing `deploymentmanager`, `networksecurity`, `iap` on the
service project produces a cluster-create error at minute 11 of the OCM apply:
`The following required APIs are not enabled in the project: ...`. The
provider doesn't pre-check.

### 1.4 Relax `iam.allowedPolicyMemberDomains` so OSD can grant impersonation

OSD WIF needs to grant `roles/iam.serviceAccountTokenCreator` to
`redhat-ocm@osd-management.iam.gserviceaccount.com` and a Red Hat group
(`sd-sre-platform-gcp-access@redhat.com`). If your org has the default
restrictive policy (allow only your own customer ID), these grants get
rejected.

Two ways:

**Option A — org-wide allow Red Hat's customer ID (broader):**

```yaml
# /tmp/policy.yaml
name: organizations/<GCP_ORG_ID>/policies/iam.allowedPolicyMemberDomains
spec:
  rules:
  - values:
      allowedValues:
      - <your-gcp-customer-id>  # existing — keep
      - C019dadek               # Red Hat (add)
```

```bash
gcloud org-policies set-policy /tmp/policy.yaml
```

**Option B — project-level override on the service project only (narrower; recommended):**

```yaml
# /tmp/policy-service-project.yaml
name: projects/<SERVICE_PROJECT>/policies/iam.allowedPolicyMemberDomains
spec:
  rules:
  - allowAll: true
```

```bash
gcloud org-policies set-policy /tmp/policy-service-project.yaml
```

Option B leaves the rest of the org locked down.

**Pitfall**: org policy changes take **5–10 min to propagate**. If the
Terraform apply runs immediately after, the binding still fails with
`User ... is not in permitted organization`. Verify propagation by manually
adding a Red Hat principal as a member on any SA in the service project,
then removing it — once the manual binding succeeds, the policy has
propagated.

---

## 2. Auth state needed by Terraform

```bash
gcloud auth application-default login          # GCP ADC
ocm login                                       # OCM cached session
export OSDGOOGLE_TOKEN=$(ocm token)             # provider env var
```

**Pitfall**: OCM offline tokens expire in ~15 min of inactivity. The
`osdgoogle_cluster` resource polls cluster state for up to 60 min, and
the token can expire mid-poll. Symptom: `polling cluster state failed: ...
access and refresh tokens are unavailable or expired`. The cluster is fine
server-side — re-export `OSDGOOGLE_TOKEN` and re-apply.

For a more robust path: use a Red Hat IAM **service account**
(client_id/client_secret) instead of an offline token. Configure
`provider "osdgoogle" { client_id = ..., client_secret = ... }` (or
`OSDGOOGLE_CLIENT_ID` / `OSDGOOGLE_CLIENT_SECRET` env vars).

**Recovery if the token expires mid-poll:** the cluster keeps installing
server-side; only the Terraform poller dies. The cluster is missing from
state but exists in OCM. To recover:

```bash
# 1. Find the cluster ID OCM created
ocm list clusters --columns id,name,state --parameter search="name='osd-poc'"

# 2. Import it into Terraform state
export OSDGOOGLE_TOKEN=$(ocm token)
cd 02-cluster
terraform import osdgoogle_cluster.osd <CLUSTER_ID>

# 3. Wait for cluster to reach READY (out of band, fresh token)
until [ "$(ocm describe cluster <CLUSTER_ID> | awk '/^State:/{print $2}')" = "ready" ]; do
  sleep 120
done

# 4. Re-apply to create the IdP (which requires cluster ready)
terraform apply
```

---

## 3. Build the provider locally (only if using the IdP resource)

The PoC uses `osdgoogle_identity_provider`, which is a custom addition to
`rh-mobb/terraform-provider-osd-google` on branch
`feat/osdgoogle-identity-provider`. Skip this section if your build of the
provider already ships it.

Clone the fork (or upstream + cherry-pick the branch) somewhere outside
this repo:

```bash
git clone https://github.com/<your-fork>/terraform-provider-osd-google.git
cd terraform-provider-osd-google
git checkout feat/osdgoogle-identity-provider
make build              # produces ./terraform-provider-osd-google
```

Configure the dev override in `~/.terraformrc`:

```hcl
provider_installation {
  dev_overrides {
    "registry.terraform.io/rh-mobb/osd-google" = "/abs/path/to/terraform-provider-osd-google"
  }
  direct {}
}
```

**Pitfall**: `terraform init` warns to remove dev_overrides for init runs.
Ignore — init still succeeds; Terraform will read the locally-built binary
at plan/apply time.

How this works internally: `provider/provider.go` imports
`github.com/terraform-redhat/terraform-provider-rhcs/provider/identityprovider`
as a Go module and registers its `New` function in `Resources()`. The
resource's `Metadata()` uses `req.ProviderTypeName + "_identity_provider"`,
so the same code becomes `osdgoogle_identity_provider` under our provider.
Zero duplicated source; transitive deps include rhcs's full go.sum
(aws-sdk-go entries appear in `go.sum`, but the linker drops them — binary
is unaffected).

---

## 4. Phase 1 — Shared VPC infrastructure (`01-shared-vpc/`)

Creates:
- Shared VPC host enable on the host project
- Service project attach
- VPC `osd-shared-vpc` (regional, no auto-subnets, Private Google Access on all subnets)
- Three subnets: control-plane `/28`, compute `/24`, PSC `/29`
- Cloud NAT on `osd-shared-vpc-router`
- Intra-VPC allow firewall rule

```bash
cd 01-shared-vpc
terraform init
terraform apply \
  -var=host_project_id="$HOST_PROJECT" \
  -var=service_project_id="$SERVICE_PROJECT"
```

Exposed outputs (consumed by Phase 2 via `terraform_remote_state`):
`host_project_id`, `service_project_id`, `network_name`, `network_self_link`,
`control_plane_subnet`, `compute_subnet`, `psc_subnet`, `region`.

**Pitfall**: Phase 1 only enables `compute.googleapis.com`. Step 1.3 above
covers the rest — apply it BEFORE Phase 2, not after.

---

## 5. Phase 2 — Cluster (`02-cluster/`)

### Files

| File | Purpose |
|---|---|
| `providers.tf` | `hashicorp/google ~> 6.0`, `rh-mobb/osd-google` (dev override) |
| `main.tf` | Reads Phase 1 outputs, defines locals (region, project IDs, subnets) |
| `variables.tf` | `cluster_name`, `openshift_version`, `compute_nodes`, `admin_password` (sensitive) |
| `wif.tf` | `osdgoogle_wif_config` (OCM) + `module "wif_gcp"` (workload identity pool + SAs + role bindings) |
| `kms.tf` | KMS key ring + crypto key + dedicated SA + 2 IAM bindings (KMS SA + Compute Engine Service Agent) |
| `host_iam.tf` | 9 bindings on host project: 3 SAs × 3 roles (Compute Network Admin, Compute Security Admin, DNS Admin) |
| `cluster.tf` | `osdgoogle_cluster` composing `wif_config_id` + `gcp_network` + `private_service_connect` + `gcp_encryption_key` + `private = true` |
| `idp.tf` | `osdgoogle_identity_provider` (htpasswd `admin`) — depends on cluster.id |
| `bastion.tf` | CentOS Stream 9 VM + IAP firewall; reaches cluster API over PSC |
| `outputs.tf` | Cluster id/api/console, bastion SSH command, IdP login command |

### Critical resource composition (the four features on one cluster)

```hcl
resource "osdgoogle_cluster" "osd" {
  name           = var.cluster_name
  product        = "osdtrial"           # see pitfall below
  cloud_region   = local.region
  gcp_project_id = local.service_project_id
  wif_config_id  = osdgoogle_wif_config.wif.id
  version        = local.openshift_version
  compute_nodes  = var.compute_nodes
  ccs_enabled    = true
  private        = true

  gcp_network = {                                          # Shared VPC
    vpc_name             = local.network_name
    vpc_project_id       = local.host_project_id           # = host, not service
    compute_subnet       = local.compute_subnet
    control_plane_subnet = local.control_plane_subnet
  }
  private_service_connect = {                              # PSC
    service_attachment_subnet = local.psc_subnet
  }
  gcp_encryption_key = {                                   # CMEK
    kms_key_service_account = google_service_account.kms.email
    key_location            = local.region
    key_name                = google_kms_crypto_key.osd.name
    key_ring                = google_kms_key_ring.osd.name
  }
  security = { secure_boot = true }

  depends_on = [
    module.wif_gcp,
    google_kms_crypto_key_iam_member.kms_sa,
    google_kms_crypto_key_iam_member.compute_agent,
    google_project_iam_member.host,            # all 9 host bindings
  ]
}
```

### Apply order — DO NOT skip the two-phase trick

The `osd-wif-gcp` module uses `for_each` over `osdgoogle_wif_config.gcp.service_accounts`,
whose keys are only known after OCM creates the WIF config. Terraform can't
plan `for_each` with unknown keys. **Apply the WIF config first, then the rest:**

```bash
cd 02-cluster
terraform init
export TF_VAR_admin_password='<strong password — 14+ chars, mixed case + digit + symbol>'
export OSDGOOGLE_TOKEN=$(ocm token)

# Phase 2a — WIF config only (OCM resource, no GCP cost)
terraform apply -target=osdgoogle_wif_config.wif

# Phase 2b — everything else
terraform apply
```

**Pitfall**: htpasswd password validator (in the rhcs IdP code) requires
≥14 chars, ASCII only, uppercase, lowercase, and digit/symbol. Weak passwords
fail at plan time.

### Cluster `waiting` state (the host-IAM diagnostic)

After `osdgoogle_cluster.osd: Still creating...`, OCM may put the cluster in
`waiting` with:

> User action required: Could not validate the shared subnets in the host
> project ... Make sure the following service account(s) [osd-deployer-upba,
> osd-control-plane-upba, machine-api-gcp-upba] ... has been granted the
> Compute Network Admin, Compute Security Admin, and DNS Administrator roles
> via the host project IAM.

`host_iam.tf` does this — but the cluster needs to be RE-validated by OCM
after the grants land. If the apply errors at this point, re-run
`terraform apply`; OSD will recheck on the next polling cycle (within a few
minutes).

### `Duplicate cluster name` on retry

If the apply died mid-cluster-create (e.g., OCM token expiry, host IAM
missing), the cluster exists in OCM but isn't in Terraform state. The next
apply errors `Duplicate cluster name`. Recover with:

```bash
CLUSTER_ID=$(ocm list clusters --parameter "search=name='osd-poc'" --columns id --no-headers)
terraform import osdgoogle_cluster.osd "$CLUSTER_ID"
terraform apply
```

### `product = "osdtrial"` vs what OCM actually creates

We set `product = "osdtrial"` in HCL. OCM may upgrade to `Product: osd`
based on the org's available quota and the GCP marketplace subscription
(`Subscription type: marketplace-gcp`). This is OCM-side behavior, not a
provider bug. Trial behavior (no OSD service fee for 60 days) only kicks
in if the org has trial slots available AND no full subscription is taking
precedence. Verify with `ocm describe cluster <id>` after creation.

---

## 6. Verification

Run `02-cluster/verify.sh` for a single-shot summary of all four features,
or run the checks individually:

### 6.1 OCM-side

```bash
CLUSTER_ID=$(cd 02-cluster && terraform output -raw cluster_id)
ocm describe cluster "$CLUSTER_ID" | head -30
ocm get "/api/clusters_mgmt/v1/clusters/$CLUSTER_ID" | jq '.gcp.authentication, .api'
```

Look for:
- `State: ready`
- `API Listening: internal` (PSC working)
- `gcp.authentication.kind: WifConfig` (WIF working)
- API URL is a `*.p2.openshiftapps.com` private hostname (PSC working)

### 6.2 GCP-side

```bash
# CMEK on worker boot disks
gcloud compute disks list --project="$SERVICE_PROJECT" \
  --filter="name~osd-poc AND name!~bastion" \
  --format='value(name,diskEncryptionKey.kmsKeyName)'
# Expect every row to include "projects/<SERVICE_PROJECT>/.../cryptoKeys/osd-poc-key"

# Compute instances in host-project subnets (Shared VPC)
gcloud compute instances list --project="$SERVICE_PROJECT" \
  --filter="name~osd-poc AND name!~bastion" \
  --format='value(name,networkInterfaces.subnetwork[0])'
# Subnetworks should reference the HOST project, not service project
```

### 6.3 IdP via bastion (end-to-end)

```bash
cd 02-cluster
eval $(terraform output -raw bastion_ssh_command)
# Inside the bastion:
#   oc login --username=admin --password='<your password>' <api_url>
#   oc whoami        # should return "admin"
```

Bastion `oc` is installed by the startup script. First `gcloud ssh
--tunnel-through-iap` may take 30–60s to provision OS Login. Cluster API
hostname is the `api_url` Terraform output.

`oc whoami` returning `admin` confirms the IdP works. A `Forbidden` on
`oc get nodes` is *expected* — htpasswd admin is just an authenticated
user, not cluster-admin. To get cluster-admin, add an
`osdgoogle_cluster_admin` resource or grant the role manually via OCM.

---

## 7. Destroy

```bash
cd 02-cluster
export OSDGOOGLE_TOKEN=$(ocm token)
terraform destroy
```

`terraform destroy` removes resources in reverse dependency order. The
`osdgoogle_cluster` destroy takes ~15 min server-side; `terraform destroy`
polls until OCM confirms. Phase 1 (`01-shared-vpc/`) can stay — Phase 2
is self-contained and reusable.

**Pitfall**: destroy will fail if the OCM token expires mid-poll. If so,
re-export `OSDGOOGLE_TOKEN` and re-run `terraform destroy` — it'll resume.

**Pitfall**: WIF custom roles in GCP enter a 7-day soft-delete state after
destroy. If you rebuild within 7 days with the same `cluster_name` (which
determines `role_prefix`), the recreate fails with "Role ... already
exists". Either:
- Use a different `cluster_name` for the rebuild (changes `role_prefix`), or
- `gcloud iam roles undelete <ROLE_ID> --project="$SERVICE_PROJECT"` for each
  soft-deleted role, then `gcloud iam roles delete` again.

---

## 8. Rebuild from this runbook

The whole point of writing this is to confirm it's correct end-to-end.
Sequence:

1. `terraform destroy` in `02-cluster/` (Phase 1 stays).
2. Wait for destroy to finish.
3. Follow this runbook from section 2 down (skipping Phase 1).
4. Verify per section 6.
5. Diff outputs vs. the first build — same cluster shape, different ID.

If anything in section 5 or 6 differs from the first build's outputs
(other than IDs/timestamps), the runbook has a gap; update it and re-run.

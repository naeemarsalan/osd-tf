#!/bin/bash
# Verify the four PoC features on the live cluster.
# Run from 02-cluster/ after `terraform apply` completes.
set -euo pipefail

CLUSTER_ID=$(terraform output -raw cluster_id)
CLUSTER_NAME=$(terraform output -raw cluster_name)
HOST_PROJECT=$(cd ../01-shared-vpc && terraform output -raw host_project_id)
SERVICE_PROJECT=$(cd ../01-shared-vpc && terraform output -raw service_project_id)

echo "=== OCM cluster summary ==="
ocm describe cluster "$CLUSTER_ID" | grep -E "^(State|API URL|API Listening|VPC-Name|Control-Plane-Subnet|Compute-Subnet|Provider|Region|SecureBoot):"

echo
echo "=== WIF: cluster authentication kind ==="
ocm get "/api/clusters_mgmt/v1/clusters/$CLUSTER_ID" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('gcp.authentication:', json.dumps(d.get('gcp',{}).get('authentication',{}), indent=2))"

echo
echo "=== PSC: API endpoint should be private (*.p2.openshiftapps.com or *.internal) ==="
ocm describe cluster "$CLUSTER_ID" | awk '/^API URL:/'

echo
echo "=== Shared VPC: cluster VMs live in HOST project subnets ==="
gcloud compute instances list --project="$SERVICE_PROJECT" \
  --filter="name~$CLUSTER_NAME AND name!~bastion" \
  --format='value(name,networkInterfaces[0].subnetwork)' | head
echo "(Subnetwork URLs should reference projects/$HOST_PROJECT/, not $SERVICE_PROJECT/)"

echo
echo "=== CMEK: cluster boot disks reference the customer key ==="
gcloud compute disks list --project="$SERVICE_PROJECT" \
  --filter="name~$CLUSTER_NAME AND name!~bastion" \
  --format='value(name,diskEncryptionKey.kmsKeyName)' | head
echo "(All rows should include projects/$SERVICE_PROJECT/.../cryptoKeys/$CLUSTER_NAME-key)"

echo
echo "=== IdP: htpasswd admin user registered in OCM ==="
ocm get "/api/clusters_mgmt/v1/clusters/$CLUSTER_ID/identity_providers" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); [print(i['name'], i['type']) for i in d.get('items',[])]"

echo
echo "=== Bastion IAP SSH command ==="
terraform output -raw bastion_ssh_command
echo
echo
echo "From the bastion, test the IdP end-to-end with:"
echo "  oc login --username=admin --password='<your password>' \\"
echo "    $(terraform output -raw api_url)"

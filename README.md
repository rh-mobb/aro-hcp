# ARO HCP Reference Deployment

Reference implementation for deploying **Azure Red Hat OpenShift Hosted Control Plane (ARO HCP)** using Terraform for Azure prerequisites and idempotent bash scripts wrapping `az aro hcp`.

Based on [bennerv/ARO-HCP 0.0.2](https://github.com/bennerv/ARO-HCP/releases/tag/0.0.2) (`2026-06-30-preview` API).

## Architecture

After `make all` the subscription has two resource groups: a **customer RG** (Terraform + cluster ARM resource) and a **managed RG** (resource provider; deny assignment). The hosted control plane is not in the customer subscription.

Detailed resource inventory, RBAC scopes, CIDRs, and diagrams: **[`docs/architecture.md`](docs/architecture.md)**.

```text
make all
  ├── bootstrap.sh          # az aro hcp CLI extension
  ├── terraform apply       # RG, network, Key Vault, 13 identities, RBAC
  ├── cluster.sh create     # az aro hcp cluster create
  └── nodepool.sh create    # default worker node pool
```

| Layer | Tool | Resources |
|-------|------|-----------|
| Prerequisites | Terraform (azurerm + azapi) | RG, NSG, VNet, subnets, Key Vault, etcd KMS key, 13 MIs, RBAC |
| Cluster API | Bash + `az aro hcp` | Cluster, node pools, credentials, external-auth |
| Service-owned | ARO HCP RP | Managed RG, worker VMs, hosted control plane |

**AzAPI follow-up:** cluster and node pools can move to `azapi_resource` (`Microsoft.RedHatOpenShift/hcpOpenShiftClusters@2026-06-30-preview`) for full Terraform lifecycle. Scripts are intentionally first-class today.

## Prerequisites

- Azure subscription **allow-listed** for ARO HCP preview
- **Owner**, or **Contributor** + **User Access Administrator**, on the subscription or customer RG (UAA is required: Terraform creates role assignments)
- **`make external-auth` only:** permission to create an Entra **app registration** (and client secret). Application Administrator is **not** always required — see [Operator permissions](docs/architecture.md#operator-permissions)
- Tools: Azure CLI `>= 2.67.0`, Terraform `>= 1.9`, `jq`, `oc >= 4.20` (for external-auth), optional `shellcheck`, `shfmt`, `tflint`, `bats`, `pre-commit`

Register resource providers (done by Terraform by default):

```bash
az provider register --namespace Microsoft.RedHatOpenShift --wait
```

### Valid regions

`australiaeast`, `brazilsouth`, `canadacentral`, `centralindia`, `eastus2`, `switzerlandnorth`, `uksouth`, `westeurope`

### Quota

At least **8 vCPU** of your worker VM SKU in the target region (default `Standard_D4s_v6` × 2 replicas = 8 vCPU). Add more if creating additional node pools.

## Quick start

```bash
cp config/cluster.env.example config/cluster.env
# Edit LOCATION, CLUSTER_NAME, RESOURCE_GROUP, versions

make bootstrap
make all                 # apply + cluster + default nodepool (~30-60 min)
make kubeconfig          # admin creds (24h TTL)
make external-auth       # optional Entra + console
```

## Makefile targets

| Target | Description |
|--------|-------------|
| `make help` | List targets |
| `make fmt` / `lint` / `test` | Format, lint, test |
| `make bootstrap` | Install `az aro hcp` extension |
| `make init` / `plan` / `apply` | Terraform prerequisites |
| `make cluster` / `nodepool` | Idempotent HCP create |
| `make all` | Full deploy to usable cluster |
| `make kubeconfig` | Admin kubeconfig → `.kube/config` |
| `make revoke-credentials` | Revoke admin creds |
| `make versions` | List OpenShift versions for region |
| `make external-auth` | Entra app + external-auth + console secret |
| `make external-auth-delete` | Remove external-auth |
| `make destroy` | Teardown (external-auth → nodepool → cluster → terraform) |

## Configuration

Copy [`config/cluster.env.example`](config/cluster.env.example) to `config/cluster.env`. Scripts and Make read this file; Terraform vars are passed via `TF_VAR_*` from the Makefile.

## Git hygiene

```bash
pre-commit install       # optional local hooks
make fmt lint test       # before every commit
```

- Branch from `main` using `feat/`, `fix/`, `chore/`, `docs/` prefixes
- Conventional Commits: `type(scope): description`
- Update [`CHANGELOG.md`](CHANGELOG.md) in the same commit as operator-visible changes; do not log debug/WIP iterations
- Never commit secrets, `config/cluster.env`, `*.tfstate`, or kubeconfig files
- See [`AGENTS.md`](AGENTS.md) for agent-specific rules

## Mapping to 0.0.2 guide

| 0.0.2 section | This repo |
|---------------|-----------|
| Install extension | `make bootstrap` |
| Register RP / create RG | `terraform apply` |
| Network + KeyVault + identities | `terraform apply` |
| Cluster create | `scripts/cluster.sh` / `make cluster` |
| Node pools | `scripts/nodepool.sh` |
| Credentials | `scripts/credentials.sh` |
| get-versions | `scripts/versions.sh` |
| External auth | `scripts/external-auth.sh` |

## RBAC note

Role assignments follow the **0.0.2 CLI guide** (VNet-scoped CAPI/CCM/ingress/image-registry). Older Bicep in `references/` assigns some roles at subnet scope — do not copy that pattern.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `roleAssignments/write` AuthorizationFailed | Missing User Access Administrator | Grant Owner, or Contributor **and** UAA, on the RG/subscription |
| Cluster create permission error | Wrong RBAC scope on MI | Verify VNet-scoped roles in `terraform/identities.tf` |
| Credential POST 404 | Cluster not ready | Wait for `provisioningState: Succeeded` |
| Admin kubeconfig fails | CLI issue | `credentials.sh` falls back to REST async flow |
| Credential expired | 24h TTL | `make kubeconfig` again |
| `az ad app create` / `credential reset` Insufficient privileges | Tenant disables user app registration | Application Developer or Cloud Application Administrator, **or** have an admin create the app and add you as owner. Not the same as Azure Owner. See [permissions](docs/architecture.md#operator-permissions) |
| AADSTS65001 consent error | User consent disabled | Admin consent for Azure CLI Graph scopes and/or the OIDC app |
| Console 503 / degraded CO | No external-auth | `make external-auth` |
| `oc login` fails | Missing plugin | Use `oc` 4.20+ with `oc-oidc` |
| Invalid redirect URI | Entra app mismatch | Re-run external-auth create |

## Known issues

### `TargetDown`: `azure-disk-csi-driver-node-metrics` (ARO HCP preview)

After cluster and node pool creation, the observability console may show:

> **TargetDown** — 100% of `azure-disk-csi-driver-node-metrics` targets in `openshift-cluster-csi-drivers` have been unreachable for more than 15 minutes.

**Impact:** Monitoring/alerting only. **Disk storage is not affected.**

The Azure Disk CSI driver itself is healthy (`azure-disk-csi-driver-node` DaemonSet ready, PVCs bind to `managed-csi`). Prometheus cannot scrape the metrics Service because of a TLS certificate name mismatch on hosted control plane clusters:

| Expected by ServiceMonitor | Actual cert SAN |
|----------------------------|-----------------|
| `azure-disk-csi-driver-node-metrics.ocm-arohcpprod-<…>-<cluster>.svc` | `azure-disk-csi-driver-node-metrics.openshift-cluster-csi-drivers.svc` |

Prometheus reports: `tls: failed to verify certificate: x509: certificate is valid for …openshift-cluster-csi-drivers.svc…, not …ocm-arohcpprod-….svc`.

**Workaround:** Safe to ignore for eval/demo workloads. To confirm CSI is functional:

```bash
oc get ds -n openshift-cluster-csi-drivers azure-disk-csi-driver-node
oc get co csi-snapshot-controller
```

**Tracking:** Platform bug — report to Red Hat/ARO HCP preview support if you need clean observability dashboards.

## Local references

The `references/` folder may contain cloned ARO-HCP repos and hackathon guides (gitignored clones). These are **source material only**, not deployed.

## Optional: remote Terraform state

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstate"
    container_name       = "tfstate"
    key                  = "aro-hcp.terraform.tfstate"
  }
}
```

# ARO HCP Reference Deployment

Reference implementation for deploying **Azure Red Hat OpenShift Hosted Control Plane (ARO HCP)** using Terraform (azurerm + AzAPI) for Azure prerequisites, the HCP cluster, and the default node pool. Bash scripts wrap `az aro hcp` for credentials, extra node pools, and external-auth. Targets the `2026-06-30-preview` API.

**Documentation:** [https://rh-mobb.github.io/aro-hcp/](https://rh-mobb.github.io/aro-hcp/) — prerequisites, permissions by step, external-auth, and architecture. Local preview: `make docs-preview`.

## Architecture

After `make cluster.<name>.apply` the subscription has two resource groups: a **customer RG** (Terraform + cluster ARM resource) and a **managed RG** (resource provider; deny assignment). The hosted control plane is not in the customer subscription.

Documentation: **[`docs/README.md`](docs/README.md)** (index) · **[Architecture](docs/architecture.md)** (resources, diagrams) · **[Permissions by step](docs/prerequisites/full-stack.md#permissions-by-deployment-step)** (least privilege).

```text
make cluster.public.apply
  ├── setup.sh              # az aro hcp CLI extension (credentials / extra pools)
  └── terraform apply       # modules: network, identities, cluster (+ optional jumpbox)
```

| Layer | Tool | Resources |
|-------|------|-----------|
| Prerequisites + cluster | Terraform (azurerm + azapi) | RG, NSG, VNet, subnets, Key Vault, etcd KMS key, optional `redhat-pull-secret`, 13 HCP MIs + ESO identity, RBAC, `hcpOpenShiftClusters`, default `nodePools` |
| Cluster API (scripts) | Bash + `az aro hcp` | Extra node pools, credentials, external-auth |
| Service-owned | ARO HCP RP | Managed RG, worker VMs, hosted control plane |

Last-pool DELETE is blocked ([OCPBUGS-86702](https://issues.redhat.com/browse/OCPBUGS-86702)). `make cluster.<name>.destroy` removes the default node pool from Terraform state, then `terraform destroy` (cluster ARM delete cascades remaining pools). Extra node pools: `NAME=np-2 bash scripts/nodepool.sh create`.

## Prerequisites

Complete **[Account prerequisites](docs/prerequisites/account.md)** before deploy. Summary:

| Requirement | Notes |
|-------------|-------|
| ARO HCP preview **allow-list** | Not an Azure role — subscription must be enrolled |
| **Contributor + User Access Administrator** on customer RG | Minimum for `make cluster.<name>.apply` (Terraform writes 28 role assignments). **Owner** also works but is broader |
| **`make cluster.<name>.external-auth` only** | Entra app registration rights — **Application Administrator not required** when users may register apps; see [External auth guide](docs/guides/external-auth-entra-id.md) |
| Tools | Azure CLI `>= 2.67.0`, Terraform `>= 1.9`, `jq`, `oc >= 4.20`, optional `sshuttle`, `make setup` for `az aro hcp` |

Per-target permission matrix: **[Full-stack deployment](docs/prerequisites/full-stack.md#permissions-by-deployment-step)**.

Register `Microsoft.RedHatOpenShift` if not already registered (Terraform also registers providers):

```bash
az provider register --namespace Microsoft.RedHatOpenShift --wait
```

Valid regions and quota details: [Account prerequisites](docs/prerequisites/account.md).

## Quick start

See **[Quick start guide](docs/getting-started/quick-start.md)**. Minimal path:

```bash
cp -r clusters/public clusters/my-cluster
# Edit clusters/my-cluster/terraform.tfvars (location, cluster_name, versions)

make setup
make cluster.my-cluster.init
make cluster.my-cluster.plan
make cluster.my-cluster.apply           # prereqs + cluster + default nodepool (~30-60 min)
make cluster.my-cluster.kubeconfig      # admin creds (24h TTL)
make cluster.my-cluster.external-auth   # Entra + console (required for usable console)
```

Committed examples: [`clusters/public`](clusters/public/terraform.tfvars) (public API/ingress) and [`clusters/private`](clusters/private/terraform.tfvars) (private + jump box). See [`clusters/README.md`](clusters/README.md).

## Makefile targets

Global:

| Target | Description |
|--------|-------------|
| `make help` | List targets |
| `make fmt` / `lint` / `test` | Format, lint, test |
| `make setup` | Install `az aro hcp` extension |

Per cluster (`<name>` = directory under `clusters/`):

| Target | Description |
|--------|-------------|
| `make cluster.<name>.init` | Terraform init (per-cluster state) |
| `make cluster.<name>.plan` | Terraform plan |
| `make cluster.<name>.apply` | Terraform apply: prereqs + cluster + default node pool |
| `make cluster.<name>.destroy` | Teardown (external-auth → state-rm last pool → terraform destroy) |
| `make cluster.<name>.kubeconfig` | Admin kubeconfig → `.kube/config` |
| `make cluster.<name>.revoke-credentials` | Revoke admin creds |
| `make cluster.<name>.versions` | List enabled HCP versions for `location` |
| `make cluster.<name>.jump-key` | Generate `clusters/<name>/jump` + `jump.pub` |
| `make cluster.<name>.jump` | Print sshuttle command (foreground) |
| `make cluster.<name>.sshuttle.connect` | Start sshuttle in the background (`clusters/<name>/sshuttle.pid`) |
| `make cluster.<name>.sshuttle.disconnect` | Stop background sshuttle for this profile |
| `make cluster.<name>.external-auth` | Entra app + external-auth + console |
| `make cluster.<name>.bootstrap` | OpenShift GitOps + Web Terminal + Compliance + ESO (optional) |
| `make cluster.<name>.external-auth-delete` | Remove external-auth |

## Configuration

Each cluster is a directory under [`clusters/`](clusters/) with a `terraform.tfvars`. `make cluster.<name>.plan` / `apply` / `destroy` pass that file with `-var-file` (beats leftover `TF_VAR_*` for keys in the file). Scripts after apply read terraform outputs, then fall back to the same file.

| Variable | Default | Notes |
|----------|---------|-------|
| `cluster_name` | (required) | Also prefixes identities and, unless overridden, RG / VNet / subnet / NSG names. |
| `resource_group_name` | `<cluster_name>-rg` | Optional. Same pattern: `managed` / `vnet` / `worker` / `integration` / `nsg`. |
| `api_visibility` | `Public` | Create-time only: `Public` or `Private`. |
| `ingress_visibility` | `Public` | Create-time only: `Public`, `Private`, or `Disabled`. Console / `*.apps`. |
| `enable_jumpbox` | `false` | When `true`, Terraform creates the Fedora jump VM. |
| `jump_ssh_source_prefix` | (empty) | Required when jump is on; SSH 22 allowed from this CIDR only (use your `/32`). |
| `pull_secret_path` | (empty) | Optional. Path to a Red Hat dockerconfigjson. When set, Terraform writes Key Vault `redhat-pull-secret`. Prefer `PULL_SECRET_PATH=... make cluster.<name>.apply` (Make exports `TF_VAR_pull_secret_path`). Never commit the file. |

The jump public key is `clusters/<name>/jump.pub` (create with `make cluster.<name>.jump-key`); Make exports it as `TF_VAR_jump_ssh_public_key` when the file exists. It is not stored in `terraform.tfvars`.

When `enable_jumpbox = true`, `make cluster.<name>.plan` / `apply` require `clusters/<name>/jump.pub` (`make cluster.<name>.jump-key` first).

Per-cluster Terraform state: `clusters/<name>/infrastructure.tfstate` (see [`clusters/README.md`](clusters/README.md)).

## Git hygiene

```bash
pre-commit install       # optional local hooks
make fmt lint test       # before every commit
```

- Branch from `main` using `feat/`, `fix/`, `chore/`, `docs/` prefixes
- Conventional Commits: `type(scope): description`
- Update [`CHANGELOG.md`](CHANGELOG.md) in the same commit as operator-visible changes; do not log debug/WIP iterations
- Never commit secrets, operator `clusters/*/terraform.tfvars` (except committed examples), `*.tfstate`, or kubeconfig files
- See [`AGENTS.md`](AGENTS.md) for agent-specific rules

## Operator workflow

| Step | This repo |
|------|-----------|
| Install extension | `make setup` |
| Register RP / create RG | `make cluster.<name>.apply` |
| Network + KeyVault + identities | `make cluster.<name>.apply` |
| Cluster create | `make cluster.<name>.apply` (AzAPI in `modules/cluster`) |
| Node pools | Default: Terraform. Extra: `scripts/nodepool.sh` |
| Credentials | `make cluster.<name>.kubeconfig` |
| get-versions | `make cluster.<name>.versions` |
| External auth | `make cluster.<name>.external-auth` |
| GitOps operators | `make cluster.<name>.bootstrap` |

## RBAC note

Role assignments use VNet-scoped CAPI/CCM/ingress/image-registry (not subnet scope). Older Bicep in `references/` assigns some roles at subnet scope — do not copy that pattern.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Cluster public does not exist` on kubeconfig | GNU Make exported `CLUSTER_NAME=public` (profile dir) shadowed Azure `cluster_name` | Fixed in Makefile (`CLUSTER_PROFILE` + `unexport CLUSTER_NAME`). Update scripts; re-run `make cluster.<profile>.kubeconfig` |
| Last node pool delete 409 | OCPBUGS-86702 | Use `make cluster.<name>.destroy`. Do not `terraform destroy` alone. |
| Destroy 409: cluster is deleting | Interrupted destroy; ARM delete still running | Re-run `make cluster.<name>.destroy` (waits and retries). |
| Cluster create permission error | Wrong RBAC scope on MI | Verify VNet-scoped roles in `modules/identities/` |
| Credential POST 404 | Cluster not ready | Wait for `provisioningState: Succeeded` |
| Admin kubeconfig fails | CLI issue | `credentials.sh` falls back to REST async flow |
| Credential expired | 24h TTL | `make cluster.<name>.kubeconfig` again |
| `az ad app create` / `credential reset` Insufficient privileges | Tenant disables user app registration | Application Developer or Cloud Application Administrator, **or** have an admin create the app and add you as owner. Not the same as Azure Owner. See [Entra permissions](docs/guides/external-auth-entra-id.md#directory-roles-least-privilege) |
| AADSTS65001 consent error | User consent disabled | Admin consent for Azure CLI Graph scopes and/or the OIDC app |
| Console "Application is not available" / 503 / degraded `console` CO | No external-auth (console OAuth secret missing) | `make cluster.<name>.external-auth` |
| GitOps CSV never Succeeded | Channel not in catalog for this OCP version | Bump `gitops/bootstrap/subscription.yaml` `channel` to the current `gitops-1.x` (see [GitOps guide](docs/guides/gitops.md)) |
| GitOps bundle ImagePullBackOff `registry.redhat.io` | HCP pull secret is only the service ACR | `PULL_SECRET_PATH=<dockerconfigjson> make cluster.<name>.apply` stores it in Key Vault; `make cluster.<name>.bootstrap` creates `kube-system/additional-pull-secret` |
| Duplicate GitOps / Web Terminal operators | Installed from Software Catalog as well as GitOps | Delete the extra Subscription; keep the GitOps-managed one |
| `oc login` fails | Missing plugin | Use `oc` 4.20+ with `oc-oidc` |
| Invalid redirect URI | Entra app mismatch | Re-run external-auth create |
| `oc` cannot reach API hostname | `api_visibility = "Private"` without VNet path or API DNS | `make cluster.<name>.sshuttle.connect`; `make cluster.<name>.private-dns`; merge `clusters/<name>/operator-hosts.snippet` into `/etc/hosts` if needed |
| Console unreachable from the internet | `ingress_visibility = "Private"` | `make cluster.<name>.sshuttle.connect`; `private-dns` + hosts snippet for console hostname |
| Console secret apply timeout (private) | `oc` without sshuttle or stale public DNS for `*.aroapp-hcp.io` | sshuttle + `private-dns` + hosts snippet; `make cluster.<name>.console-secret` |
| plan/apply: missing clusters/<name>/jump.pub | Jump enabled without a key | `make cluster.<name>.jump-key` |
| Jump SSH timeout | Source IP not in `jump_ssh_source_prefix` | Set prefix to your /32 and re-apply |

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

Per-cluster local state is the default (`clusters/<name>/infrastructure.tfstate`). For remote backends, init with `-backend-config` pointing at a unique key per cluster (see [`terraform/versions.tf`](terraform/versions.tf) and [`clusters/README.md`](clusters/README.md)).

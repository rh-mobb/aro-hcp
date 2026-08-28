# Account Prerequisites

Layer **0** — required before any `make cluster.<name>.*` command that touches Azure (except local-only targets such as `jump-key` or `bootstrap`).

## Azure subscription

| Requirement | Notes |
|-------------|-------|
| **ARO HCP preview allow-list** | Not an Azure role. The subscription must be enrolled for the preview or cluster create fails regardless of RBAC. Contact your Microsoft account team or Red Hat if create returns enrollment errors. |
| Dedicated or shared subscription | All customer-side resources live in one customer resource group plus a service-managed resource group. |
| Azure CLI signed in | `az login` — confirm with `az account show` (subscription name, tenant, user). |

### Valid regions

`australiaeast`, `brazilsouth`, `canadacentral`, `centralindia`, `eastus2`, `switzerlandnorth`, `uksouth`, `westeurope`

### Compute quota

| Workload | Default | Minimum vCPU |
|----------|---------|--------------|
| Default node pool | `Standard_D4s_v6` × 2 replicas | **8 vCPU** in `location` |
| Optional jump box | `Standard_D2s_v6` × 1 | **+2 vCPU** when `enable_jumpbox = true` |
| Extra node pools | `scripts/nodepool.sh` | Add replicas × SKU vCPU per pool |

Check quota:

```bash
az vm list-usage --location <region> -o table | grep -i standardDSv6Family
```

Request increases in the Azure portal (**Subscriptions → Usage + quotas**) if needed.

## RBAC scope and least privilege

Terraform creates **everything in one customer resource group** (VNet, Key Vault, 13 user-assigned identities, 28 role assignments to those identities, HCP cluster ARM resource). Grant the deployer one of:

| Role combination | Scope | Least privilege? | When to use |
|------------------|-------|------------------|-------------|
| **Contributor** + **User Access Administrator** | Customer RG (recommended) or subscription | **Yes** — minimum built-in pair for this repo | Default recommendation |
| **Owner** | Customer RG or subscription | No — includes UAA and more | Acceptable when policy allows only Owner |
| **Contributor** only | Any | **Insufficient** | Fails on `Microsoft.Authorization/roleAssignments/write` |
| **User Access Administrator** only | Any | **Insufficient** | Cannot create network, Key Vault, cluster |

**Why User Access Administrator:** [`modules/identities/`](../../modules/identities/) assigns 28 platform roles to service identities and **Key Vault Administrator** to the deployer. Contributor cannot write role assignments.

RG-scoped **Contributor + UAA** is enough for this repo’s default layout. A pre-existing VNet or Key Vault in **another** resource group also requires **Contributor + UAA** (or Owner) on that scope.

### Resource provider registration

Terraform registers providers it needs (`Microsoft.RedHatOpenShift`, `Microsoft.Network`, `Microsoft.KeyVault`, `Microsoft.ManagedIdentity`, `Microsoft.Authorization`). Registration is a **subscription-level** action:

```bash
az provider register --namespace Microsoft.RedHatOpenShift --wait
```

An operator with **RG-only** Contributor + UAA cannot register providers if they are not already registered. Options:

- One-time registration by a subscription **Contributor** or **Owner**.
- Pre-register providers before handing off RG-scoped deploy access.

### Splitting duties (optional)

| Person | Azure RBAC | Runs |
|--------|------------|------|
| Platform engineer | Contributor + UAA on customer RG | `init`, `plan`, `apply`, `destroy` |
| Cluster operator | Contributor on `hcpOpenShiftClusters` resource | `kubeconfig`, `revoke-credentials`, `external-auth` |
| Identity admin | Entra **Application Developer** (or app owner) | `external-auth` Entra steps only, if split |
| Break-glass | OpenShift `cluster-admin` via 24h kubeconfig | Console secret, `rbac-user` / `rbac-group` |

See [Full-stack deployment — permissions by step](full-stack.md#permissions-by-deployment-step) for every `make` target.

## Operator tooling

| Tool | Minimum | Purpose |
|------|---------|---------|
| Azure CLI | >= 2.67.0 | Azure + Entra (`az ad`) |
| `az aro hcp` extension | 0.0.2 (via `make bootstrap`) | Credentials, external-auth, extra node pools |
| Terraform | >= 1.9 | Infrastructure |
| `jq` | any recent | Scripts, credential parsing |
| `oc` | >= 4.20 | External-auth console secret, optional RBAC |
| `sshuttle` | optional | Private API / private ingress via jump box |
| `shellcheck`, `shfmt`, `tflint`, `bats`, `pre-commit` | optional | `make lint` / `make test` |

Install the CLI extension:

```bash
make bootstrap
```

## Firewall allowlist

If the operator machine uses egress filtering, allow HTTPS (443) to at least:

| Endpoint | Purpose |
|----------|---------|
| `management.azure.com` | Azure Resource Manager |
| `login.microsoftonline.com` | Azure AD / Entra sign-in |
| `graph.microsoft.com` | `az ad` app registration commands |
| `registry.terraform.io`, `releases.hashicorp.com` | Terraform providers |
| `github.com`, `objects.githubusercontent.com` | Extension wheel / modules |

Cluster nodes and the hosted control plane use Azure service networking; this table is for the **operator workstation** only.

## Verify before init

```bash
az account show --query '{subscription:name,id:id,tenant:tenantId,user:user.name}' -o json
az provider show --namespace Microsoft.RedHatOpenShift --query registrationState -o tsv
env | grep '^TF_VAR_' || true   # leftover TF_VAR_* can override cluster tfvars — see AGENTS.md
```

## Next steps

- [Full-stack deployment](full-stack.md) — workflow and per-target permissions
- [Quick start](../getting-started/quick-start.md)

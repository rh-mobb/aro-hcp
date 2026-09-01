# Full-Stack Deployment

Layer **1** — one platform team runs the complete lifecycle from this repository using `clusters/<name>/terraform.tfvars`.

## What Terraform creates

| Component | Module |
|-----------|--------|
| Resource group, VNet, NSG, worker + integration subnets | [`modules/network/`](../../modules/network/) |
| Key Vault, etcd KMS key, optional pull-secret KV secret, 13 HCP identities + ESO identity, 28 operator RBAC assignments + ESO Key Vault Secrets User | [`modules/identities/`](../../modules/identities/) |
| HCP cluster + default node pool (AzAPI) | [`modules/cluster/`](../../modules/cluster/) |
| Optional Fedora jump VM | [`modules/jumpbox/`](../../modules/jumpbox/) |

You provide `clusters/<name>/terraform.tfvars`. Per-cluster state defaults to `clusters/<name>/infrastructure.tfstate`.

## Before you start

1. Complete [Account prerequisites](account.md).
2. Copy an example profile:

   ```bash
   cp -r clusters/public clusters/my-cluster
   # or clusters/private for private API/ingress + jump box
   ```

3. When `enable_jumpbox = true`:

   ```bash
   make cluster.my-cluster.jump-key   # writes clusters/my-cluster/jump + jump.pub
   ```

## Cluster profiles

| Profile | Directory | Key settings |
|---------|-----------|--------------|
| Public API + ingress | [`clusters/public/`](../../clusters/public/) | `api_visibility = "Public"`, `ingress_visibility = "Public"`, `enable_jumpbox = false` |
| Private API + ingress + jump | [`clusters/private/`](../../clusters/private/) | `api_visibility = "Private"`, `ingress_visibility = "Private"`, `enable_jumpbox = true`, set `jump_ssh_source_prefix` |

## Deployment workflow

```bash
make setup                         # once per machine — az aro hcp extension
make cluster.<name>.init
make cluster.<name>.plan               # validates OpenShift versions for location
make cluster.<name>.apply              # ~30–60 min
make cluster.<name>.kubeconfig         # 24h admin creds → .kube/config
make cluster.<name>.external-auth      # Entra + console — required for usable console
make cluster.<name>.bootstrap   # optional: GitOps + Web Terminal + Compliance + ESO
```

Private API or ingress:

```bash
make cluster.<name>.sshuttle.connect      # background sshuttle (clusters/<name>/sshuttle.pid)
make cluster.<name>.sshuttle.disconnect   # stop background sshuttle
make cluster.<name>.private-dns         # customer Private DNS for api.*.aroapp-hcp.io (after apply)
# merge clusters/<name>/operator-hosts.snippet into /etc/hosts when public DNS still resolves console/apps
```

Teardown:

```bash
make cluster.<name>.external-auth-delete   # recommended before destroy if Entra app exists
make cluster.<name>.destroy
```

## Permissions by deployment step

Permissions fall into three planes: **Azure RBAC**, **Microsoft Entra ID**, and **OpenShift**. Subscription Owner does **not** grant Entra app registration rights.

### Summary table

| Step | `make` target | Azure RBAC (minimum) | Entra directory | OpenShift |
|------|---------------|----------------------|-----------------|-----------|
| Install CLI extension | `setup` | None | None | None |
| Generate jump SSH key | `cluster.<name>.jump-key` | None | None | None |
| List enabled versions | `cluster.<name>.versions` | **Reader** on subscription (read `hcpOpenShiftVersions`) | None | None |
| Terraform init | `cluster.<name>.init` | None (local providers) | None | None |
| Terraform plan | `cluster.<name>.plan` | **Reader** on subscription + customer RG; same as apply if state exists | None | None |
| Create / update infra | `cluster.<name>.apply` | **Contributor + UAA** or **Owner** on customer RG; subscription **Contributor** once if RPs not registered | None | None |
| Admin kubeconfig | `cluster.<name>.kubeconfig` | **Contributor** on cluster resource (or RG) | None | None |
| Revoke admin creds | `cluster.<name>.revoke-credentials` | **Contributor** on cluster resource | None | None |
| External auth + console | `cluster.<name>.external-auth` | **Contributor** on cluster (`externalAuths` write) | App create + credential reset — see [Entra guide](../guides/external-auth-entra-id.md) | **cluster-admin** kubeconfig (24h) for console secret |
| Remove external auth | `cluster.<name>.external-auth-delete` | **Contributor** on cluster | App **owner** or role with `Application.ReadWrite.All` delegated via Azure CLI | Optional admin kubeconfig to delete secret |
| Print sshuttle command | `cluster.<name>.jump` | None (reads tfvars / outputs) | None | None |
| Start sshuttle (background) | `cluster.<name>.sshuttle.connect` | None (reads tfvars / outputs; jump VM must exist) | None | None |
| Stop sshuttle | `cluster.<name>.sshuttle.disconnect` | None | None | None |
| Customer Private DNS (private API) | `cluster.<name>.private-dns` | **Contributor** on customer RG (Private DNS zone + VNet link + A records); **Reader** on managed RG (`hypershift.local` A record) | None | None |
| Retry console OAuth secret | `cluster.<name>.console-secret` | None | App credential reset if re-running | **cluster-admin** kubeconfig + sshuttle for private API |
| GitOps + operator baseline | `cluster.<name>.bootstrap` | **Key Vault Secrets User** (or deployer Key Vault Administrator) to `get` `redhat-pull-secret` unless `PULL_SECRET_PATH` is set | None | **cluster-admin** kubeconfig; sshuttle if API is private |
| Destroy | `cluster.<name>.destroy` | Same as **apply** (delete cluster, network, identities); runs `private-dns-delete` when API is private | Same as **external-auth-delete** if cleaning Entra app manually first | Optional admin kubeconfig if deleting console secret |
| Extra node pool | `scripts/nodepool.sh create` | **Contributor** on cluster (`nodePools` write) | None | None |

### Azure RBAC detail by target

#### `make cluster.<name>.apply` and `destroy`

| Need | Why |
|------|-----|
| `Microsoft.Resources/subscriptions/resourceGroups/write` | Create customer RG |
| `Microsoft.Network/*` on RG | VNet, subnets, NSG, associations |
| `Microsoft.KeyVault/vaults/write`, `.../keys/write`, `.../secrets/write` | Etcd KMS Key Vault and key; optional `redhat-pull-secret` when `pull_secret_path` is set |
| `Microsoft.ManagedIdentity/userAssignedIdentities/write` | 13 HCP identities + ESO workload identity |
| `Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/write` | ESO federated credential (cluster OIDC issuer → named ServiceAccount) |
| `Microsoft.Authorization/roleAssignments/write` | 28 operator assignments + ESO Key Vault Secrets User + Key Vault Administrator for deployer (**requires UAA or Owner**) |
| `Microsoft.RedHatOpenShift/hcpOpenShiftClusters/write` | Cluster ARM resource |
| `Microsoft.RedHatOpenShift/hcpOpenShiftClusters/nodePools/write` | Default node pool |
| `Microsoft.Compute/*` (when jump enabled) | Jump VM, NIC, public IP |
| Provider register (subscription) | If `Microsoft.RedHatOpenShift` not registered — see [Account prerequisites](account.md#resource-provider-registration) |

**Least privilege:** **Contributor + User Access Administrator** at customer RG scope. Avoid subscription **Owner** when RG-scoped roles satisfy policy.

**Typical failure without UAA:**

```text
AuthorizationFailed: ... 'Microsoft.Authorization/roleAssignments/write'
```

#### `make cluster.<name>.plan`

Reads Terraform state, existing RG resources, and ARM `hcpOpenShiftVersions` for version validation. **Reader** on subscription and customer RG is enough for a greenfield plan. If plan must reflect changes to existing deployer-owned resources, match **apply** permissions.

#### `make cluster.<name>.versions`

Runs [`hack/versions/`](../../hack/versions/) — lists `Microsoft.RedHatOpenShift/locations/hcpOpenShiftVersions`. Requires **Reader** on the subscription (or custom role with `.../hcpOpenShiftVersions/read`).

#### `make cluster.<name>.kubeconfig` / `revoke-credentials`

Calls `az aro hcp cluster request-credential` / `revoke-credential`. Requires **Contributor** (or custom role with credential actions) on the **cluster resource** or parent RG. No Entra directory roles.

#### `make cluster.<name>.external-auth`

| Plane | Minimum |
|-------|---------|
| Azure | **Contributor** on cluster — creates `externalAuths` child resource |
| Entra | Create app, SP, optional claims, client secret — [External auth guide](../guides/external-auth-entra-id.md) |
| OpenShift | Valid admin **kubeconfig** — applies `openshift-config` console secret |

Console is not usable until this step completes (ClusterOperator `console` stays degraded without the OAuth secret).

#### `make cluster.<name>.bootstrap`

| Plane | Minimum |
|-------|---------|
| Azure | **Key Vault Secrets User** (or Key Vault Administrator) on the customer vault — `get` `redhat-pull-secret`. Skip if `kube-system/additional-pull-secret` already exists or `PULL_SECRET_PATH` is set. |
| Entra | None |
| OpenShift | Valid admin **kubeconfig**; **sshuttle** if `api_visibility = Private` |

Installs OpenShift GitOps, publishes `aro-platform-metadata`, and syncs [`gitops/`](../../gitops/) (Web Terminal, Compliance, External Secrets Operator). When external-auth already ran, patches the default Argo CD instance for Entra OIDC (HCP has no in-cluster OAuth, so Dex “Log in via OpenShift” cannot work). Store the Red Hat dockerconfigjson with `PULL_SECRET_PATH=~/pull-secret.txt make cluster.<name>.apply` (Key Vault) then bootstrap. See [GitOps bootstrap](../guides/gitops.md).

#### `make cluster.<name>.destroy`

Same Azure permissions as **apply** (delete resources). Run **external-auth-delete** first if you need to remove the Entra app registration; destroy does not call Entra automatically.

### Optional: custom Azure roles

Built-in **Contributor + UAA** is the supported operator path. For stricter policy, a **custom role** at customer RG scope can combine:

- Resource write actions listed above for network, Key Vault (including `vaults/secrets/write` when uploading `redhat-pull-secret`), identities, compute (jump), and Red Hat OpenShift cluster/node pool resources
- `Microsoft.Authorization/roleAssignments/write` (UAA equivalent)
- Exclude subscription-wide actions you do not need

GitOps bootstrap, if not run by the deployer, also needs **Key Vault Secrets User** (`vaults/secrets/get`) on the customer vault.

Maintaining parity with [`modules/identities/`](../../modules/identities/) role assignment set is the operator’s responsibility if you deviate from UAA.

### Entra and OpenShift (external-auth only)

Full step-by-step, consent, and directory role matrix: **[External authentication with Entra ID](../guides/external-auth-entra-id.md)**.

Quick reference:

| Tenant setting | Operator needs |
|----------------|----------------|
| **Users can register applications** = Yes | No directory admin role; operator becomes app owner |
| That setting = No | **Application Developer** (least privilege) or **Cloud Application Administrator** |

**Not required for default script path:** Global Administrator, Application Administrator, Microsoft Graph application permissions, tenant-wide Graph admin consent for the cluster OIDC app.

## Post-deploy checks

```bash
az aro hcp cluster show -g <rg> -n <cluster> --query provisioningState -o tsv
az aro hcp cluster nodepool show -g <rg> --cluster-name <cluster> -n np-1 --query provisioningState -o tsv
oc get co console   # after external-auth
```

## Related

- [Architecture — operator permissions](../architecture.md#operator-permissions) — diagrams and Entra/OpenShift detail
- [Architecture — identities and RBAC](../architecture.md#identities-and-rbac) — service identity role scopes (VNet, not subnet)
- [Quick start](../getting-started/quick-start.md)

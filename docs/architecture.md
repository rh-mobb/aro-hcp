# ARO HCP reference deployment architecture

This document describes the Azure, Entra, and OpenShift resources that result from this repository after `make cluster.<name>.apply` (and optionally `make cluster.<name>.kubeconfig` / `make cluster.<name>.external-auth`). Names below use the defaults from [`clusters/public/terraform.tfvars`](../clusters/public/terraform.tfvars). Substitute your `terraform.tfvars` values when reading the Azure portal.

This is a **customer-side** reference. Terraform provisions prerequisites, the HCP cluster, and the default node pool via AzAPI (`2026-06-30-preview`). Bash wrappers call `az aro hcp` for credentials, extra node pools, and external-auth. The hosted control plane itself runs in the ARO HCP service, not as VMs in the customer subscription.

**Operator guides:** [Documentation site](https://rh-mobb.github.io/aro-hcp/) · [Account prerequisites](prerequisites/account.md) · [Full-stack deployment and per-step permissions](prerequisites/full-stack.md) · [External auth with Entra ID](guides/external-auth-entra-id.md)

Diagrams are [Mermaid](https://mermaid.js.org/) and render on GitHub.

## Contents

- [Trust boundary](#trust-boundary)
- [Deploy pipeline](#deploy-pipeline)
- [Operator permissions](#operator-permissions)
- [Resultant resources](#resultant-resources)
- [Customer resource group](#customer-resource-group)
- [Network](#network)
- [Jump box (optional)](#jump-box-optional)
- [Key Vault and etcd KMS](#key-vault-and-etcd-kms)
- [Identities and RBAC](#identities-and-rbac)
- [Cluster ARM resource](#cluster-arm-resource)
- [Default node pool](#default-node-pool)
- [Managed resource group](#managed-resource-group)
- [Credentials and optional Entra](#credentials-and-optional-entra)
- [Lifecycle](#lifecycle)
- [Ownership matrix](#ownership-matrix)

## Trust boundary

ARO HCP splits the classic ARO model: the control plane is hosted by the service; workers stay in the customer VNet.

| Aspect | This deployment |
|--------|-----------------|
| Control plane | Service-owned management cluster. No control-plane VMs in the customer subscription. |
| Worker nodes | Customer subscription. NICs attach to the customer worker subnet. Compute objects live in the managed resource group. |
| Cluster ARM handle | `Microsoft.RedHatOpenShift/hcpOpenShiftClusters` in the **customer** resource group. |
| Data-plane Azure objects | Managed resource group (`managed_resource_group_name`), created and locked by the resource provider. |
| Minimum workers | 2 replicas of `Standard_D4s_v6` by default (8 vCPU quota). When `enable_jumpbox = true`, add **+2 vCPU** of `Standard_D2s_v6`. |

```mermaid
flowchart TB
    subgraph customer["Customer Azure subscription"]
        operator["Operator / make"]
        subgraph custRg["Customer RG"]
            prereqs["Terraform prereqs"]
            armCluster["hcpOpenShiftClusters"]
        end
        subgraph mrg["Managed RG"]
            workers["Worker VMs, disks, LB, DNS"]
        end
        vnet["Customer VNet and subnets"]
    end

    subgraph service["ARO HCP service"]
        rp["Resource provider"]
        hcp["Hosted control plane"]
    end

    entra["Microsoft Entra ID"]

    operator --> prereqs
    prereqs --> armCluster
    armCluster -->|"create / reconcile"| rp
    rp --> hcp
    rp --> mrg
    workers --> vnet
    hcp -.->|"VNet integration subnet"| vnet
    operator -.->|"make cluster.<name>.external-auth"| entra

    classDef fillCust fill:#e7f5ff,stroke:#1971c2,color:#000
    classDef fillSvc fill:#e5dbff,stroke:#5f3dc4,color:#000
    classDef fillOpt fill:#fff4e6,stroke:#e67700,color:#000
    class operator,custRg,mrg,vnet,prereqs,armCluster,workers fillCust
    class rp,hcp fillSvc
    class entra fillOpt
```

Dashed lines are supporting or optional paths.

## Deploy pipeline

`make` is the interface. Cluster and default node-pool create are AzAPI resources, **not** Terraform `local-exec`.

```mermaid
flowchart TB
    start["cp -r clusters/public clusters/my-cluster"] --> all["make cluster.my-cluster.apply"]

    subgraph allSteps["make cluster.<name>.apply"]
        boot["bootstrap.sh"] --> apply["terraform apply"]
        apply --> cluster["module.cluster azapi hcp_cluster"]
        cluster --> nodepool["module.cluster azapi node_pool"]
    end

    all --> allSteps
    allSteps --> kube["make cluster.<name>.kubeconfig — optional"]
    kube --> auth["make cluster.<name>.external-auth — optional"]
    allSteps --> destroy["make cluster.<name>.destroy"]

    classDef fillStart fill:#d3f9d8,stroke:#2f9e44,color:#000
    classDef fillTf fill:#e7f5ff,stroke:#1971c2,color:#000
    classDef fillCli fill:#ffe8cc,stroke:#d9480f,color:#000
    classDef fillOpt fill:#fff4e6,stroke:#e67700,color:#000
    classDef fillDestroy fill:#ffe3e3,stroke:#c92a2a,color:#000
    class start fillStart
    class apply,cluster,nodepool fillTf
    class boot fillCli
    class kube,auth fillOpt
    class destroy fillDestroy
```

| Stage | Tool | What it creates |
|-------|------|-----------------|
| `make bootstrap` | `scripts/bootstrap.sh` | Installs the `az aro hcp` CLI extension wheel (0.0.2). No Azure resources. |
| `make cluster.<name>.apply` | Terraform `azurerm` + `azapi` | Customer RG, network, Key Vault, etcd key, 13 identities, 28 operator role assignments, `hcpOpenShiftClusters`, default `nodePools/np-1`. |
| `make cluster.<name>.kubeconfig` | `az aro hcp cluster request-credential` | Local `.kube/config` only. Admin credential TTL is 24 hours. |
| `make cluster.<name>.external-auth` | Entra + `az aro hcp cluster external-auth` | Entra app, `externalAuths/entra`, console client secret in the cluster. |

`make cluster.<name>.plan` / `apply` / `destroy` pass `clusters/<name>/terraform.tfvars` with `-var-file`. Scripts after apply read terraform outputs, then fall back to the same file.

## Operator permissions

Step-by-step least-privilege tables for every `make cluster.<name>.*` target: **[Full-stack deployment — permissions by step](prerequisites/full-stack.md#permissions-by-deployment-step)**. Entra OIDC detail: **[External auth with Entra ID](guides/external-auth-entra-id.md)**.

Permissions fall into three planes. Azure RBAC on the subscription does **not** grant Microsoft Entra directory rights, and the reverse is also true.

```mermaid
flowchart TB
    op["Operator signed in to Azure CLI"]

    subgraph azure["Azure RBAC — subscription or customer RG"]
        rbac["Owner or Contributor plus User Access Administrator"]
        preview["ARO HCP preview allow-list"]
        quota["Compute quota for worker SKU"]
    end

    subgraph entra["Microsoft Entra ID — tenant"]
        userApps["Users can register applications = Yes"]
        dirRole["Otherwise Application Developer or Cloud Application Administrator"]
    end

    subgraph ocp["OpenShift — after kubeconfig"]
        adminKube["24h cluster-admin kubeconfig"]
    end

    op --> rbac
    op --> preview
    op --> quota
    rbac --> apply["make cluster.<name>.apply / kubeconfig"]
    userApps -.->|"tenant allows user app create"| ext["make cluster.<name>.external-auth"]
    dirRole -.->|"tenant blocks user app create"| ext
    apply --> adminKube
    adminKube --> ext

    classDef fillOp fill:#d3f9d8,stroke:#2f9e44,color:#000
    classDef fillAz fill:#e7f5ff,stroke:#1971c2,color:#000
    classDef fillEntra fill:#fff4e6,stroke:#e67700,color:#000
    classDef fillOcp fill:#e5dbff,stroke:#5f3dc4,color:#000
    class op fillOp
    class rbac,preview,quota,apply fillAz
    class userApps,dirRole,ext fillEntra
    class adminKube fillOcp
```

### Azure RBAC — `make cluster.<name>.apply`, `destroy`, `kubeconfig`

| Requirement | Why |
|-------------|-----|
| **Owner**, or **Contributor** + **User Access Administrator**, on the subscription or customer RG | Contributor can create RG, network, Key Vault, identities, and the HCP ARM resource. It **cannot** create role assignments. Terraform writes 28 operator assignments plus Key Vault Administrator for the deployer. That needs `Microsoft.Authorization/roleAssignments/write` (User Access Administrator or Owner). |
| Resource providers registered | At minimum `Microsoft.RedHatOpenShift`. Terraform’s azurerm provider also auto-registers providers it uses (`Microsoft.Network`, `Microsoft.KeyVault`, `Microsoft.ManagedIdentity`, `Microsoft.Authorization`). Registering a provider is a **subscription** action; RG-only Contributor cannot do it if the provider is not already registered. |
| ARO HCP preview **allow-list** | Not an Azure role. The subscription must be enrolled for the preview or cluster create fails regardless of RBAC. |
| Quota | Default node pool is `Standard_D4s_v6` × 2 = **8 vCPU** in `location`. When `enable_jumpbox = true`, add **+2 vCPU** of `Standard_D2s_v6`. |

RG-scoped Owner / Contributor+UAA is enough for this repo because VNet, NSG, Key Vault, identities, and the cluster all live in one RG. A pre-existing VNet in another RG would also need UAA (or Owner) on that VNet.

`make cluster.<name>.kubeconfig` (`requestAdminCredential`) needs Contributor (or higher) on the cluster resource. It does not need Entra admin roles.

Typical failure if UAA is missing:

```text
AuthorizationFailed: The client does not have authorization to perform action
'Microsoft.Authorization/roleAssignments/write'
```

### Microsoft Entra ID — `make cluster.<name>.external-auth`

The script calls `az ad app create`, `az ad sp create`, `az ad app update` (redirect URIs + optional `groups` claims), `az ad app credential reset`, and on destroy `az ad app delete`. Those are **directory** operations. Subscription Owner does **not** imply them.

**You do not need Global Administrator.** You also do **not** always need Application Administrator.

| Tenant setting | What the operator needs |
|----------------|-------------------------|
| Entra ID → Users → User settings → **Users can register applications** = **Yes** (common default) | No directory admin role. The operator creates the app, becomes **owner**, and can set claims, create a client secret, create the service principal, and delete the app. |
| That setting = **No** (typical locked-down enterprise tenant) | A directory role that can create app registrations. Least privilege: **Application Developer** (creates apps they own, including when user registration is disabled). Broader: **Cloud Application Administrator** or **Application Administrator** (can manage **all** apps in the tenant and add credentials to them — treat as privileged). |

[Application Developer](https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference#application-developer) is the role Microsoft documents for “create app registrations when Users can register applications is No.” [Cloud Application Administrator](https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference#cloud-application-administrator) is the least-privilege role for creating enterprise applications tenant-wide; it is more power than this script needs.

What this script **does not** do (unlike some hackathon steps):

- It does **not** add Microsoft Graph application permissions (`az ad app permission add`).
- It does **not** request admin consent for Graph APIs.
- It authenticates users with `preferred_username`, not an `email` Graph claim.

So **Application Administrator is not required** for the default path, and **tenant-wide admin consent for Microsoft Graph is not required** for the default path.

Still required or commonly blocked:

| Check | Why |
|-------|-----|
| Azure CLI Microsoft Graph consent | `az ad *` uses Graph as the signed-in user (typically `Application.ReadWrite.All` delegated). First run may prompt consent. If the tenant sets **Do not allow user consent**, a Cloud Application Administrator (or Global Administrator) must grant admin consent to **Azure CLI** for those Graph scopes — that is consent for the CLI, not for the cluster’s OIDC app. |
| First console / `oc login` | Users may see “Permissions requested” for OpenID/`profile`. They can accept if user consent is allowed. If user consent is disabled, an admin must consent to **this** app (openid/profile), which is still not Application Administrator if someone else already created the app. |
| `scripts/external-auth.sh rbac-group` | Needs the Entra **group object ID** (`GROUP_ID=`). Looking groups up may need Group Reader / Directory Reader. The script also sets `groupMembershipClaims=SecurityGroup` on the app (owner can do this). |

If an admin must create the app on the operator’s behalf: create the app registration, add the operator as **owner**, then the operator can run `make cluster.<name>.external-auth` (the script reuses `CLIENT_ID` from `.external-auth/state.env`). They still need owner (or a directory role) to run `az ad app credential reset`.

Typical failures:

```text
Authorization_RequestDenied / Insufficient privileges to complete the operation
```

on `az ad app create` or `az ad app credential reset` → user registration disabled and no Application Developer / Cloud Application Administrator (or not owner of an existing app).

```text
AADSTS65001: The user or administrator has not consented
```

→ Azure CLI Graph scopes or the OIDC app need consent, not Azure RBAC.

### OpenShift RBAC — console secret and `ClusterRoleBinding`

`make cluster.<name>.external-auth` applies a secret in `openshift-config` and (optionally) `entra-cluster-admin`. That uses the **24h admin kubeconfig**, not Entra directory roles. Run `make cluster.<name>.kubeconfig` first.

Granting `cluster-admin` to an Entra user or group is OpenShift RBAC (`oc apply`). It does not change Azure or Entra admin roles.

### Permissions by `make` target

Summary — full Azure action list and split-role options: [Full-stack deployment](prerequisites/full-stack.md#permissions-by-deployment-step).

| Target | Azure RBAC (minimum) | Entra directory | OpenShift |
|--------|----------------------|-----------------|-----------|
| `make bootstrap` | None | None | None |
| `make cluster.<name>.jump-key` | None | None | None |
| `make cluster.<name>.versions` | Reader on subscription | None | None |
| `make cluster.<name>.init` | None | None | None |
| `make cluster.<name>.plan` | Reader on subscription + customer RG | None | None |
| `make cluster.<name>.apply` | Contributor + UAA (or Owner) on customer RG; subscription Contributor once if RPs not registered | None | None |
| `make cluster.<name>.kubeconfig` / `revoke-credentials` | Contributor on cluster (or RG) | None | None |
| `make cluster.<name>.external-auth` | Contributor on cluster (`externalAuths` write) | App create + credential reset — see [Entra guide](guides/external-auth-entra-id.md) | Admin kubeconfig (24h) for console secret |
| `make cluster.<name>.external-auth-delete` | Contributor on cluster | App owner or directory role for `az ad app delete` | Optional admin kubeconfig to delete secret |
| `make cluster.<name>.jump` | None | None | None |
| `make cluster.<name>.destroy` | Same as apply | Same as external-auth-delete if cleaning Entra app | Optional admin kubeconfig |
| `scripts/nodepool.sh` (extra pools) | Contributor on cluster (`nodePools` write) | None | None |

## Resultant resources

After a successful `make cluster.<name>.apply`, the customer subscription contains two resource groups. Example names:

| Resource group | Example name | Created by | Purpose |
|----------------|--------------|------------|---------|
| Customer | `my-cluster-rg` | Terraform | Network, Key Vault, identities, RBAC, cluster ARM resource, node-pool child resource. |
| Managed | `my-cluster-managed` | ARO HCP resource provider | Worker compute and service-owned Azure objects. Deny assignment blocks customer writes. |

```mermaid
flowchart TB
    subgraph sub["Customer subscription"]
        subgraph rg["Customer RG — my-cluster-rg"]
            nsg["NSG — my-cluster-nsg"]
            vnet["VNet — my-cluster-vnet 10.0.0.0/16"]
            kv["Key Vault — cust-kv-xxxxxxxxxxxx"]
            etcdKey["Key — etcd-data-kms-encryption-key"]
            ids["13 user-assigned identities"]
            rbac["28 operator role assignments + Key Vault Administrator"]
            cluster["hcpOpenShiftClusters/my-cluster"]
            np["nodePools/np-1"]
        end

        subgraph mrg["Managed RG — my-cluster-managed"]
            deny["Deny assignment"]
            vms["Worker VMs × replicas"]
            disks["OS disks"]
            nics["NICs in customer worker subnet"]
            lb["Outbound load balancer"]
            dns["Delegated apps DNS zone"]
            mrgRbac["RP-managed role assignments"]
        end
    end

    kv --> etcdKey
    cluster --> np
    cluster -->|"platform.managedResourceGroup"| mrg
    vnet --> nsg
    nics --> vnet
    ids --> cluster
    rbac --> ids
    rbac --> vnet
    rbac --> nsg
    rbac --> kv

    classDef tf fill:#e7f5ff,stroke:#1971c2,color:#000
    classDef arm fill:#ffe8cc,stroke:#d9480f,color:#000
    classDef rp fill:#e5dbff,stroke:#5f3dc4,color:#000
    classDef store fill:#fff4e6,stroke:#e67700,color:#000
    class nsg,vnet,ids,rbac tf
    class kv,etcdKey store
    class cluster,np arm
    class deny,vms,disks,nics,lb,dns,mrgRbac rp
```

Exact object names inside the managed RG are chosen by the resource provider and HyperShift. Treat that group as opaque: inspect it, do not edit it.

## Customer resource group

Terraform resources live under [`modules/`](../modules/) (composed by [`terraform/`](../terraform/)). Identity count and operator assignment count are asserted in [`modules/identities/identities.tftest.hcl`](../modules/identities/identities.tftest.hcl) (13 identities, 28 operator assignments).

### Inventory

| Azure type | Default / pattern | Terraform address | Notes |
|------------|-------------------|-------------------|-------|
| Resource group | `my-cluster-rg` | `azurerm_resource_group.this` | Location from `location`. Tag `project=aro-hcp-reference`. Default `${cluster_name}-rg`. |
| Network security group | `my-cluster-nsg` | `azurerm_network_security_group.this` | Associated only with the worker subnet. Empty of custom rules; operators may add rules later. Default `${cluster_name}-nsg`. |
| Virtual network | `my-cluster-vnet` | `azurerm_virtual_network.this` | Address space `10.0.0.0/16`. Default `${cluster_name}-vnet`. |
| Subnet | `my-cluster-worker` | `azurerm_subnet.worker` | Worker subnet `10.0.0.0/24`. Private endpoint policies disabled. Default outbound access enabled. Default `${cluster_name}-worker`. |
| Subnet NSG association | — | `azurerm_subnet_network_security_group_association.worker` | Binds the customer NSG to the worker subnet. |
| Subnet | `my-cluster-integration` | `azapi_resource.vnet_integration_subnet` | `10.0.1.0/24`. Delegated to `Microsoft.RedHatOpenShift/hcpOpenShiftClusters`. Created via AzAPI because the azurerm provider cannot express this delegation. Default `${cluster_name}-integration`. |
| Subnet | `customer-jump-subnet` | `module.jumpbox[].azurerm_subnet.jump` | `10.0.2.0/28`. Optional. Only created when `enable_jumpbox = true`. |
| NSG | `customer-jump-nsg` | `module.jumpbox[].azurerm_network_security_group.jump` | SSH 22 from `jump_ssh_source_prefix` only. Only created when `enable_jumpbox = true`. |
| Public IP | `${cluster_name}-jump-pip` | `module.jumpbox[].azurerm_public_ip.jump` | Standard static, on the jump NIC. Only created when `enable_jumpbox = true`. |
| Linux VM | `${cluster_name}-jump` | `module.jumpbox[].azurerm_linux_virtual_machine.jump` | Fedora Cloud, `Standard_D2s_v6`, admin `fedora`. Only created when `enable_jumpbox = true`. |
| Key Vault | `cust-kv-` + 13-char random | `azurerm_key_vault.this` | RBAC authorization, public network access, soft-delete 7 days, purge protection off. |
| Key Vault key | `etcd-data-kms-encryption-key` | `azurerm_key_vault_key.etcd_encryption` | RSA 2048; wrap/unwrap/encrypt/decrypt/sign/verify. |
| User-assigned identity × 13 | `${cluster_name}-…` | `azurerm_user_assigned_identity.*` | See [Identities and RBAC](#identities-and-rbac). |
| Role assignment × 28 | — | `azurerm_role_assignment.this` | Operator RBAC from the 0.0.2 CLI guide. |
| Role assignment × 1 | Key Vault Administrator | `azurerm_role_assignment.deployer_key_vault_admin` | Deployer object ID so Terraform can create the etcd key. |
| HCP cluster | `my-cluster` | `azapi_resource.hcp_cluster` | `hcpOpenShiftClusters@2026-06-30-preview`. `schema_validation_enabled = false`. Timeouts 120m. |
| Node pool | `np-1` | `azapi_resource.node_pool` | Child `nodePools`. Last-pool DELETE is blocked (OCPBUGS-86702); destroy state-rms this resource first. |

This reference **does not** create a private Key Vault, private endpoint, or `privatelink.vaultcore.azure.net` zone. The demo Bicep in `references/` can; this repo sets etcd KMS `visibility` to `Public`.

## Network

```mermaid
flowchart TB
    subgraph vnet["my-cluster-vnet — 10.0.0.0/16"]
        subgraph worker["my-cluster-worker — 10.0.0.0/24"]
            nics["Worker NICs"]
            pods["Pod overlay 10.128.0.0/14"]
        end
        subgraph vis["my-cluster-integration — 10.0.1.0/24"]
            del["Delegation: Microsoft.RedHatOpenShift/hcpOpenShiftClusters"]
        end
        subgraph jump["customer-jump-subnet — 10.0.2.0/28"]
            jumpVm["Fedora jump VM"]
            jumpPip["Public IP"]
        end
    end

    nsg["my-cluster-nsg"] --> worker
    jumpNsg["customer-jump-nsg"] --> jump
    hcp["Hosted control plane"] -->|"private connectivity"| vis
    api["API/ingress Public by default / Private when api_visibility or ingress_visibility=Private"] -.-> hcp
    workers["Worker VMs in managed RG"] --> nics
    nics --> pods
    jumpPip --> jumpVm

    classDef net fill:#e7f5ff,stroke:#1971c2,color:#000
    classDef rp fill:#e5dbff,stroke:#5f3dc4,color:#000
    classDef pub fill:#c5f6fa,stroke:#0c8599,color:#000
    classDef opt fill:#fff4e6,stroke:#e67700,color:#000
    class vnet,worker,vis,nsg,del net
    class hcp,workers rp
    class api,jumpPip pub
    class jump,jumpVm,jumpNsg opt
    class nics,pods net
```

| CIDR | Role | Source |
|------|------|--------|
| `10.0.0.0/16` | VNet / machine CIDR | Terraform `address_prefix`; ARM network default `machineCidr` |
| `10.0.0.0/24` | Worker subnet | Terraform `subnet_prefix`; cluster `platform.subnetId` |
| `10.0.1.0/24` | VNet integration subnet | Terraform `vnet_integration_subnet_prefix`; cluster `platform.vnetIntegrationSubnetId` |
| `10.0.2.0/28` | Jump subnet | Terraform `jump_subnet_prefix`; optional `enable_jumpbox` |
| `10.128.0.0/14` | Pod CIDR | Terraform `pod_cidr` (ARM default) |
| `172.30.0.0/16` | Service CIDR | Terraform `service_cidr` (ARM default) |

Terraform sets `network.podCidr`, `network.serviceCidr`, `network.machineCidr`, and `network.hostPrefix` on the AzAPI cluster body.

**Outbound:** `platform.outboundType` defaults to `LoadBalancer`. The load balancer is created in the managed resource group.

**API visibility:** `Public` by default. Set `api_visibility = "Private"` in `terraform.tfvars` (create-time, immutable). **Ingress / console:** `Public` by default. Set `ingress_visibility = "Private"` for a private default ingress (console and `*.apps`). Private kube-apiserver and private ingress require a path into the VNet (this repo’s jump + sshuttle, or your own). `platform.outboundType` remains `LoadBalancer` (outbound public IP in the managed RG still exists).

**VNet integration subnet** is required for hosted-control-plane private connectivity into the customer VNet. It must remain delegated; do not place worker NICs on it.

### Jump box (optional)

Independent of API visibility. When `enable_jumpbox = true`, Terraform module [`modules/jumpbox`](../modules/jumpbox) creates a Fedora Cloud VM on `customer-jump-subnet` (`10.0.2.0/28`) with a Standard public IP and NSG allowing SSH 22 only from `jump_ssh_source_prefix`.

1. `make cluster.<name>.jump-key` — writes gitignored `clusters/<name>/jump` + `jump.pub` (plan/apply require the `.pub` when jump is on).
2. Set `enable_jumpbox = true` and `jump_ssh_source_prefix` (your `/32`) in `terraform.tfvars`.
3. `make cluster.<name>.apply` — provisions subnet, NSG, PIP, NIC, and VM (`Standard_D2s_v6`, admin `fedora`, Trusted Launch). Image default: `/communityGalleries/Fedora-5e266ba4-2250-406d-adad-5d73860d958f/images/Fedora-Cloud-44-x64/versions/latest`.
4. `make cluster.<name>.jump` — prints the foreground sshuttle command. Prefer `make cluster.<name>.sshuttle.connect` to start sshuttle in the background (`clusters/<name>/sshuttle.pid`); `make cluster.<name>.sshuttle.disconnect` stops it.
5. `make cluster.<name>.kubeconfig` still uses ARM (`requestAdminCredential`); only `oc` / API hostname traffic needs sshuttle when the API is private.
6. `make cluster.<name>.private-dns` — creates a customer-RG Private DNS zone (VNet-linked) with `api` → managed `hypershift.local` IP, optional `*.apps` when the ingress router internal LB IP is found, and writes `clusters/<name>/operator-hosts.snippet` for `/etc/hosts` when public DNS still resolves `*.aroapp-hcp.io`.

API hostname is `https://api.<id>.<region>.aroapp-hcp.io:443`. sshuttle `--dns` alone may not route `oc` correctly if the laptop still resolves public `aroapp-hcp.io` addresses — use **private-dns** and the hosts snippet as above.

Quota: **+2 vCPU** of `Standard_D2s_v6` in `location` when the jump is enabled.

## Key Vault and etcd KMS

AzAPI cluster body (`properties.etcd.dataEncryption`):

```text
keyManagementMode: CustomerManaged
encryptionType: KMS
kms.vaultName: <azurerm_key_vault.this.name>
kms.visibility: Public
kms.activeKey.name: etcd-data-kms-encryption-key
kms.activeKey.version: <azurerm_key_vault_key.etcd_encryption.version>
```

The KMS identity (`${cluster_name}-kms`) has **Key Vault Crypto User** on the vault. The cluster resource is created only after that assignment exists.

Terraform sets `purge_soft_delete_on_destroy = true` on the azurerm provider so `make cluster.<name>.destroy` can purge the vault. Redeploying without purge can collide on the random vault name only if a soft-deleted vault with the same name still exists.

## Identities and RBAC

Thirteen user-assigned identities (service + 9 control-plane operators + 3 data-plane operators). Names are `${cluster_name}-<role>` with **no** random suffix (unlike older demo Bicep).

```mermaid
flowchart TB
    svc["service"]

    subgraph cp["Control-plane operators"]
        capi["cluster-api-azure"]
        cpo["control-plane"]
        ccm["cloud-controller-manager"]
        ing["ingress"]
        disk["disk-csi-driver"]
        file["file-csi-driver"]
        img["image-registry"]
        net["cloud-network-config"]
        kms["kms"]
    end

    subgraph dp["Data-plane operators"]
        dpDisk["dp-disk-csi-driver"]
        dpFile["dp-file-csi-driver"]
        dpImg["dp-image-registry"]
    end

    svc -->|"Reader on each CP identity"| cp
    svc -->|"Federated Credential on each DP identity"| dp

    classDef fillSvc fill:#ffe8cc,stroke:#d9480f,color:#000
    classDef fillCp fill:#e7f5ff,stroke:#1971c2,color:#000
    classDef fillDp fill:#d3f9d8,stroke:#2f9e44,color:#000
    class svc fillSvc
    class capi,cpo,ccm,ing,disk,file,img,net,kms fillCp
    class dpDisk,dpFile,dpImg fillDp
```

`--user-assigned-identities` on cluster create includes the **service + 9 CP** identities only. The three data-plane identities are referenced solely under `operatorsAuthentication.userAssignedIdentities.dataPlaneOperators`, matching the demo ARM body.

### Identity catalog

| Local key | Azure name | OperatorsAuthentication slot |
|-----------|------------|------------------------------|
| `service` | `${cluster_name}-service` | `serviceManagedIdentity` |
| `cluster_api_azure` | `${cluster_name}-cluster-api-azure` | CP `cluster-api-azure` |
| `control_plane` | `${cluster_name}-control-plane` | CP `control-plane` |
| `cloud_controller_manager` | `${cluster_name}-cloud-controller-manager` | CP `cloud-controller-manager` |
| `ingress` | `${cluster_name}-ingress` | CP `ingress` |
| `disk_csi_driver` | `${cluster_name}-disk-csi-driver` | CP `disk-csi-driver` |
| `file_csi_driver` | `${cluster_name}-file-csi-driver` | CP `file-csi-driver` |
| `image_registry` | `${cluster_name}-image-registry` | CP `image-registry` |
| `cloud_network_config` | `${cluster_name}-cloud-network-config` | CP `cloud-network-config` |
| `kms` | `${cluster_name}-kms` | CP `kms` |
| `dp_disk_csi_driver` | `${cluster_name}-dp-disk-csi-driver` | DP `disk-csi-driver` |
| `dp_file_csi_driver` | `${cluster_name}-dp-file-csi-driver` | DP `file-csi-driver` |
| `dp_image_registry` | `${cluster_name}-dp-image-registry` | DP `image-registry` |

### Built-in role GUIDs

From [`modules/identities/locals.tf`](../modules/identities/locals.tf), aligned with the 0.0.2 `az aro hcp` guide:

| Local key | Role definition GUID |
|-----------|----------------------|
| `service_managed_identity` | `c0ff367d-66d8-445e-917c-583feb0ef0d4` |
| `cluster_api_provider` | `88366f10-ed47-4cc0-9fab-c8a06148393e` |
| `control_plane_operator` | `fc0c873f-45e9-4d0d-a7d1-585aab30c6ed` |
| `cloud_controller_manager` | `a1f96423-95ce-4224-ab27-4e3dc72facd4` |
| `ingress_operator` | `0336e1d3-7a87-462b-b6db-342b63f7802c` |
| `file_storage_operator` | `0d7aedc0-15fd-4a67-a412-efad370c947e` |
| `image_registry_operator` | `8b32b316-c2f5-4ddf-b05b-83dacd2d08b5` |
| `network_operator` | `be7a6435-15ae-4171-8f30-4a343eff9e8f` |
| `key_vault_crypto_user` | `12338af0-0e69-4776-bea7-57ae8d297424` |
| `reader` | `acdd72a7-3385-48ef-bd42-f606fba81ae7` |
| `federated_credential` | `ef318e2a-8334-4a05-9e4a-295a196c6a6e` |

### Operator role assignments

Scopes follow **0.0.2**: CAPI, CCM, ingress, file CSI, and image registry are assigned on the **VNet** (and NSG where listed), **not** the worker subnet. Older Bicep in `references/` still uses subnet scope for some of those roles — do not copy it.

| Key | Principal | Role | Scope |
|-----|-----------|------|-------|
| `service-vnet` | service | Service managed identity | VNet |
| `service-nsg` | service | Service managed identity | NSG |
| `capi-vnet` | cluster-api-azure | Cluster API provider | VNet |
| `service-reader-capi` | service | Reader | cluster-api-azure identity |
| `cp-vnet` | control-plane | Control plane operator | VNet |
| `cp-nsg` | control-plane | Control plane operator | NSG |
| `service-reader-cp` | service | Reader | control-plane identity |
| `ccm-vnet` | cloud-controller-manager | Cloud controller manager | VNet |
| `ccm-nsg` | cloud-controller-manager | Cloud controller manager | NSG |
| `service-reader-ccm` | service | Reader | cloud-controller-manager identity |
| `ingress-vnet` | ingress | Ingress operator | VNet |
| `service-reader-ingress` | service | Reader | ingress identity |
| `service-reader-disk-csi` | service | Reader | disk-csi-driver identity |
| `file-csi-vnet` | file-csi-driver | File storage operator | VNet |
| `file-csi-nsg` | file-csi-driver | File storage operator | NSG |
| `service-reader-file-csi` | service | Reader | file-csi-driver identity |
| `image-reg-vnet` | image-registry | Image registry operator | VNet |
| `service-reader-image-reg` | service | Reader | image-registry identity |
| `cloud-net-subnet` | cloud-network-config | Network operator | Worker subnet |
| `cloud-net-vnet` | cloud-network-config | Network operator | VNet |
| `service-reader-cloud-net` | service | Reader | cloud-network-config identity |
| `kms-kv` | kms | Key Vault Crypto User | Key Vault |
| `service-reader-kms` | service | Reader | kms identity |
| `service-fed-dp-disk` | service | Federated credential | dp-disk-csi-driver identity |
| `service-fed-dp-file` | service | Federated credential | dp-file-csi-driver identity |
| `service-fed-dp-image` | service | Federated credential | dp-image-registry identity |
| `dp-file-subnet` | dp-file-csi-driver | File storage operator | Worker subnet |
| `dp-file-nsg` | dp-file-csi-driver | File storage operator | NSG |

Control-plane disk CSI has **no** network-scoped Azure role in this set — only service Reader on the identity. Data-plane file CSI is the DP identity that receives file-storage operator on subnet + NSG.

```mermaid
flowchart LR
    subgraph scopes["RBAC scopes"]
        vnet["VNet"]
        nsg["NSG"]
        subnet["Worker subnet"]
        kv["Key Vault"]
        mi["Each operator identity"]
    end

    svc["service identity"] --> vnet
    svc --> nsg
    svc --> mi

    capi["cluster-api-azure"] --> vnet
    cpo["control-plane"] --> vnet
    cpo --> nsg
    ccm["cloud-controller-manager"] --> vnet
    ccm --> nsg
    ing["ingress"] --> vnet
    file["file-csi-driver"] --> vnet
    file --> nsg
    img["image-registry"] --> vnet
    net["cloud-network-config"] --> vnet
    net --> subnet
    kms["kms"] --> kv
    dpFile["dp-file-csi-driver"] --> subnet
    dpFile --> nsg

    classDef fillScope fill:#fff4e6,stroke:#e67700,color:#000
    classDef fillId fill:#e7f5ff,stroke:#1971c2,color:#000
    class vnet,nsg,subnet,kv,mi fillScope
    class svc,capi,cpo,ccm,ing,file,img,net,kms,dpFile fillId
```

## Cluster ARM resource

Created in the customer RG:

```text
/subscriptions/<sub>/resourceGroups/my-cluster-rg/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/my-cluster
```

API version: `2026-06-30-preview`.

```mermaid
sequenceDiagram
    participant Make
    participant TF as Terraform
    participant ARM
    participant RP as ARO HCP RP

    Make->>TF: terraform apply
    TF->>ARM: PUT hcpOpenShiftClusters@2026-06-30-preview
    ARM->>RP: validated create
    RP-->>ARM: 201 + Azure-AsyncOperation
    Note over RP: managed RG, hosted control plane, DNS
    ARM-->>TF: provisioningState Succeeded
    TF->>ARM: PUT hcpOpenShiftClusters/.../nodePools/np-1
    ARM->>RP: node pool create
    RP-->>ARM: Succeeded
```

AzAPI body in [`modules/cluster/cluster.tf`](../modules/cluster/cluster.tf) (`schema_validation_enabled = false`, create/delete timeouts 120m):

| Property | Value |
|----------|--------|
| `name` / `location` | `cluster_name` / `location` |
| `properties.version.id` / `channelGroup` | `cluster_version` / `cluster_channel`. Plan fails unless `cluster_version` is an enabled stream in `hcpOpenShiftVersions` for `location`. |
| `platform.subnetId` | Worker subnet |
| `platform.vnetIntegrationSubnetId` | AzAPI integration subnet |
| `platform.networkSecurityGroupId` | Customer NSG |
| `platform.managedResourceGroup` | `managed_resource_group_name` |
| `platform.outboundType` | `LoadBalancer` |
| `etcd` KMS | Customer-managed; vault visibility Public |
| `api.visibility` | `Public` (or `api_visibility`) |
| `ingress.type` | `Public` (or `ingress_visibility`: Public, Private, Disabled) |
| identity + `operatorsAuthentication` | Service + 9 CP identities; DP map; service MI |

ARM properties always set (not left to RP defaults):

| Property | Default |
|----------|---------|
| `network.networkType` | `OVNKubernetes` |
| `network.podCidr` | `10.128.0.0/14` |
| `network.serviceCidr` | `172.30.0.0/16` |
| `network.machineCidr` | `10.0.0.0/16` |
| `network.hostPrefix` | `23` |
| `api.visibility` | `Public` unless `api_visibility = "Private"` |
| `ingress.type` | `Public` unless `ingress_visibility` is `Private` or `Disabled` |
| `platform.outboundType` | `LoadBalancer` |
| `clusterImageRegistry.state` | `Enabled` |

Create is idempotent: Terraform apply is a no-op when state matches.

Useful read-back fields after `Succeeded` (Terraform outputs `api_url` / `console_url` from `response_export_values`):

| Field | Meaning |
|-------|---------|
| `properties.provisioningState` | Cluster ARM state |
| `properties.api.url` | Kubernetes API |
| `properties.console.url` | OpenShift console; Entra redirect is this URL + `/auth/callback` |
| `properties.dns` | Customer-facing DNS (API / apps) filled by the service |

## Default node pool

Child resource:

```text
.../hcpOpenShiftClusters/my-cluster/nodePools/np-1
```

| Property | Default (`terraform.tfvars.example`) |
|----------|----------------------------------|
| Name | `np-1` |
| Replicas | `2` |
| VM size | `Standard_D4s_v6` |
| Version / channel | `4.22.9` / `stable`. Plan fails unless the patch is enabled in `hcpOpenShiftVersions` for `location`. |
| Subnet | Cluster `platform.subnetId` (worker subnet) |

OS disk is 64 GiB Standard SSD (`node_pool_disk_size_gib` / `node_pool_disk_storage_account_type`). Extra pools: `NAME=… REPLICAS=… VM_SIZE=… bash scripts/nodepool.sh create`.

Worker VMs and disks appear in the **managed** RG. Their NICs attach to `${cluster_name}-worker` (`my-cluster-worker` in the example).

## Managed resource group

Created by the resource provider when the cluster is created. Named `managed_resource_group_name` (default `${cluster_name}-managed`). Must be unique in the subscription.

Typical contents after the default node pool is ready (names are service-generated):

| Kind | Why it exists |
|------|----------------|
| Deny assignment | Prevents customer principals from mutating RP-owned objects. Delete the **cluster**, not this RG. |
| Virtual machines | One per node-pool replica. |
| NICs | Attached to the customer worker subnet. |
| OS disks | Backing disks for workers. |
| Load balancer + public IP | `outboundType: LoadBalancer`. |
| DNS zone | Delegated apps zone; wildcard for `*.apps…` ingress. |
| Additional role assignments | RP/HyperShift identities operating on this RG (on the order of a dozen; not defined in this repo). |
| RH-managed NSG association | Service may associate an NSG with the worker subnet for platform traffic. |

Do not run `az group delete` on the managed RG. `az aro hcp cluster delete` (via `make cluster.<name>.destroy`) removes the cluster, node pools, and then the managed RG.

The hosted control plane (kube-apiserver, etcd, OAuth, console backend, operators) runs on the service management cluster. It is **not** listed in either customer resource group.

## Credentials and optional Entra

```mermaid
flowchart TB
    subgraph required["After make cluster.<name>.apply"]
        cred["make cluster.<name>.kubeconfig"]
        kube[".kube/config — 24h admin kubeconfig"]
        cred --> kube
    end

    subgraph optional["make external-auth"]
        app["Entra app registration"]
        sp["Enterprise application / service principal"]
        ext["externalAuths/entra on the cluster"]
        secret["Secret entra-console-openshift-console in openshift-config"]
        app --> sp
        app --> ext
        app --> secret
    end

    kube -.-> secret

    classDef req fill:#c5f6fa,stroke:#0c8599,color:#000
    classDef opt fill:#fff4e6,stroke:#e67700,color:#000
    class cred,kube req
    class app,sp,ext,secret opt
```

### Admin kubeconfig

`scripts/credentials.sh request` prefers `az aro hcp cluster request-credential --admin`, then falls back to REST `requestAdminCredential` (`2026-06-30-preview`). Output path: `KUBECONFIG_PATH` (default `.kube/config`). Revoke with `make revoke-credentials`. This does not create a durable Azure resource.

### External authentication

`make cluster.<name>.external-auth` (after kubeconfig). **Entra directory permissions** for this step are in [Operator permissions](#operator-permissions); subscription Owner is not enough if the tenant blocks app registration.

1. Reads `properties.console.url` and registers redirect URIs: `<console>/auth/callback` and `http://localhost:8000`.
2. Creates or reuses an Entra app (`APP_DISPLAY_NAME`, default `${cluster_name}-auth`). Stores `CLIENT_ID` in `.external-auth/state.env`.
3. Sets optional claims for `groups` on id/access/SAML tokens.
4. Rotates a client secret.
5. Creates `az aro hcp cluster external-auth` named `EXTERNAL_AUTH_NAME` (default `entra`) with:
   - issuer `https://login.microsoftonline.com/<tenant>/v2.0`
   - audience = app client ID
   - username claim `preferred_username`, `NoPrefix`
   - groups claim
   - confidential console client + public CLI client
6. Applies Kubernetes secret `entra-console-openshift-console` in `openshift-config` (client secret).

Without external-auth, the OpenShift console ClusterOperator is typically degraded (missing `console-oauth-config`). The console URL shows HTTP 503 and the OpenShift **"Application is not available"** page. Run `make cluster.<name>.external-auth`.

Helpers on `scripts/external-auth.sh`: `login` (`oc-oidc`), `rbac-user`, `rbac-group`. Those create in-cluster `ClusterRoleBinding` objects (`entra-cluster-admin`), not Azure RBAC.

```mermaid
sequenceDiagram
    participant Op as Operator
    participant Az as Azure CLI
    participant Entra as Microsoft Entra ID
    participant Cluster as HCP cluster
    participant OC as oc

    Op->>Az: cluster show console.url
    Op->>Entra: app create / update redirect URIs
    Entra-->>Op: CLIENT_ID
    Op->>Entra: credential reset
    Entra-->>Op: app credential
    Op->>Az: external-auth create
    Az->>Cluster: PUT externalAuths/entra
    Op->>OC: apply console client secret
    OC->>Cluster: secret in openshift-config
```

## Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Creating: terraform apply
    Creating --> Usable: cluster + node pool Succeeded
    Usable --> Authed: make cluster.<name>.kubeconfig
    Authed --> ConsoleReady: make external-auth
    Usable --> Destroying: make cluster.<name>.destroy
    Authed --> Destroying
    ConsoleReady --> Destroying
    Destroying --> [*]
```

`make cluster.<name>.destroy` order:

1. `external-auth.sh delete` — external-auth resource, console secret, Entra app (best-effort)
2. `terraform state rm azapi_resource.node_pool` — OCPBUGS-86702: RP rejects DELETE of the last node pool
3. `terraform destroy` — cluster ARM delete cascades remaining pools and the managed RG, then customer RG contents (identities, KV, network)

When OCPBUGS-86702 is fixed and the frontend admission 409 is removed, step 2 can be dropped.

Do not `terraform destroy` the customer RG while the cluster still exists in Azure; that fails or orphans the managed RG. Plain `terraform destroy` without the state-rm also 409s on the last pool.

```mermaid
flowchart TB
    ea["Delete external-auth + Entra app"] --> rm["state rm default node pool"]
    rm --> tf["terraform destroy — cluster then customer RG"]

    classDef step fill:#ffe3e3,stroke:#c92a2a,color:#000
    class ea,rm,tf step
```

## Ownership matrix

| Resource | Created by | Destroyed by | Customer-writable |
|----------|------------|--------------|-------------------|
| Customer RG, VNet, subnets, NSG, KV, identities, operator RBAC | Terraform | `terraform destroy` | Yes |
| `hcpOpenShiftClusters` / default `nodePools` | Terraform AzAPI | `make cluster.<name>.destroy` (state-rm last pool, then destroy) | Update via TF/ARM; do not hand-edit RP fields |
| Extra `nodePools` | `az aro hcp` | `scripts/nodepool.sh delete` or cluster delete | Via CLI |
| Managed RG contents | Resource provider / HyperShift | Cluster delete | No (deny assignment) |
| Hosted control plane | ARO HCP service | Cluster delete | No |
| Admin kubeconfig | Credential API | Expires (24h) or `revoke-credentials` | Local file only |
| Entra app + secret | `external-auth.sh` | `external-auth.sh delete` | Yes; lives in the tenant, not the RG |
| `externalAuths/entra` | `az aro hcp` | `external-auth.sh delete` | Via CLI |
| Console secret in `openshift-config` | `oc apply` | `oc delete` / external-auth delete | Yes, in-cluster |

## Related repo files

| Path | Role |
|------|------|
| [`terraform/`](../terraform/) | Thin root: module composition + optional jumpbox |
| [`modules/network/`](../modules/network/) | RG, VNet, NSG, subnets |
| [`modules/identities/`](../modules/identities/) | Key Vault, etcd key, 13 MIs, RBAC |
| [`modules/cluster/`](../modules/cluster/) | AzAPI `hcpOpenShiftClusters` + default `nodePools` |
| [`modules/jumpbox/`](../modules/jumpbox/) | Optional Fedora jump VM |
| [`hack/versions/`](../hack/versions/) | Tiny Terraform root for `make cluster.<name>.versions` |
| [`terraform/jumpbox.tf`](../terraform/jumpbox.tf) | Root jumpbox wiring (`enable_jumpbox`) |
| [`clusters/`](../clusters/) | Per-cluster `terraform.tfvars` + state |
| [`scripts/destroy.sh`](../scripts/destroy.sh) | State-rm last pool then terraform destroy |
| [`scripts/cluster.sh`](../scripts/cluster.sh) | Optional CLI cluster show/update/delete |
| [`scripts/jump.sh`](../scripts/jump.sh) | Jump SSH keygen, sshuttle connect/disconnect, foreground command |
| [`scripts/nodepool.sh`](../scripts/nodepool.sh) | Extra node pool lifecycle |
| [`scripts/credentials.sh`](../scripts/credentials.sh) | Admin kubeconfig |
| [`scripts/external-auth.sh`](../scripts/external-auth.sh) | Entra + external-auth |
| [`clusters/public/terraform.tfvars`](../clusters/public/terraform.tfvars) | Names and versions |
| [`AGENTS.md`](../AGENTS.md) | Source precedence when docs disagree |
| [`README.md`](../README.md) | Operator quickstart |

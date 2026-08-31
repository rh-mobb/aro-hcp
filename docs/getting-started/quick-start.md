# Quick Start

Deploy the example **public** cluster ([`clusters/public/`](../../clusters/public/terraform.tfvars)).

## Prerequisites

Complete [Account prerequisites](../prerequisites/account.md) first:

- ARO HCP preview allow-list on your subscription
- **Contributor + User Access Administrator** (or Owner) on the target resource group or subscription
- `Microsoft.RedHatOpenShift` provider registered
- Compute quota for default workers (8 vCPU of `Standard_D4s_v6` in your region)

Install tools:

```bash
make setup    # az aro hcp extension
```

## 1. Configure cluster

```bash
cp -r clusters/public clusters/my-cluster
# Edit clusters/my-cluster/terraform.tfvars — location, cluster_name, versions
```

Check for conflicting environment overrides:

```bash
env | grep '^TF_VAR_' || true
```

Unset or align any `TF_VAR_*` with your tfvars before apply. See [AGENTS.md](../../AGENTS.md#live-azure-deployments).

## 2. Plan and apply

```bash
make cluster.my-cluster.init
make cluster.my-cluster.plan      # fails fast if cluster_version not enabled in location
make cluster.my-cluster.apply     # ~30–60 minutes
```

Optional — list enabled OpenShift versions:

```bash
make cluster.my-cluster.versions
```

## 3. Credentials and console

```bash
make cluster.my-cluster.kubeconfig       # admin creds, 24h TTL → .kube/config
make cluster.my-cluster.external-auth    # Entra app + console OAuth secret
```

External-auth requires Entra rights separate from Azure Owner — see [External auth with Entra ID](../guides/external-auth-entra-id.md).

Optional — grant yourself OpenShift cluster-admin via Entra user:

```bash
bash scripts/external-auth.sh rbac-user
```

## 4. Verify

```bash
az aro hcp cluster show -g <resource_group> -n <cluster_name> --query provisioningState
oc get co console
oc get clusterversion
```

Console URL (from cluster show) should return HTTP 200 after external-auth.

## Private cluster profile

Use [`clusters/private/`](../../clusters/private/):

```bash
cp -r clusters/private clusters/my-private
make cluster.my-private.jump-key
# Set jump_ssh_source_prefix to your public /32 in terraform.tfvars (or export TF_VAR_jump_ssh_source_prefix)
make cluster.my-private.apply
make cluster.my-private.sshuttle.connect   # background tunnel — before oc / browser
# Or: make cluster.my-private.jump          # print foreground sshuttle command
make cluster.my-private.kubeconfig
make cluster.my-private.private-dns   # customer Private DNS for api.*.aroapp-hcp.io (+ apps when router IP is known)
# Merge clusters/my-private/operator-hosts.snippet into /etc/hosts if public DNS still resolves console/apps
make cluster.my-private.external-auth
# If console secret apply times out: make cluster.my-private.console-secret (with sshuttle running)
```

Teardown for private also removes the customer Private DNS zone (`private-dns-delete` runs automatically from `destroy`).

## Teardown

```bash
make cluster.my-cluster.external-auth-delete
make cluster.my-cluster.destroy
```

For private clusters, run `make cluster.<name>.sshuttle.connect` before `external-auth-delete` if `oc` cannot reach the API. Run `make cluster.<name>.sshuttle.disconnect` when finished.

## Related

- [Full-stack deployment](../prerequisites/full-stack.md) — permissions per step
- [Architecture](../architecture.md) — resource inventory
- [Cluster configurations](../../clusters/README.md)

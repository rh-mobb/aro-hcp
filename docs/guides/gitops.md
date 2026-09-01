# GitOps bootstrap

Optional post-deploy path: install **OpenShift GitOps** (Argo CD) and a small cloud-agnostic operator baseline from this repository. Terraform still creates the cluster. This is **not** the [validated-pattern-terraform-rosa](https://github.com/rh-mobb/validated-pattern-terraform-rosa) Helm catalog.

## When to run it

Same Make shape as ROSA validated-pattern (`cluster.<name>.bootstrap`). Repo-root `make bootstrap` is still a deprecated alias for `make setup` (CLI extension) and does **not** install GitOps.

After the cluster is `Succeeded` and you have admin kubeconfig:

```bash
# First apply (or later rotate): upload dockerconfigjson to the customer Key Vault
PULL_SECRET_PATH=~/pull-secret.txt make cluster.<name>.apply

make cluster.<name>.kubeconfig
make cluster.<name>.bootstrap
```

`bootstrap` reads Key Vault `redhat-pull-secret` (terraform output `key_vault_name` + `pull_secret_key_vault_secret_name`). You do not need the file on disk at bootstrap time if apply already stored it. `PULL_SECRET_PATH` on bootstrap still overrides Key Vault.

Private API: `make cluster.<name>.sshuttle.connect` before bootstrap so `oc` can reach the API.

External-auth is not required for bootstrap. It is required for a usable **console** (Web Terminal lives there).

## What gets installed

OLM **Classic** `Subscription`s (`installPlanApproval: Automatic`). Channels are pinned in git so a minor bump is a commit; z-stream on that channel can still roll out from the catalog.

| Operator | Namespace | Channel (in git) |
|----------|-----------|------------------|
| OpenShift GitOps | `openshift-gitops-operator` | `gitops-1.19` |
| Web Terminal | `openshift-operators` | `fast` |
| Compliance Operator | `openshift-compliance` | `stable` |
| External Secrets Operator | `external-secrets-operator` | `stable-v1` |

The GitOps operator creates the default Argo CD instance in `openshift-gitops`. Bootstrap then publishes ConfigMap `aro-platform-metadata` in that namespace (Terraform outputs: ESO client ID, tenant, Key Vault URI) and plants a root `Application` (`cluster-config`) that syncs `gitops/overlays/public` or `gitops/overlays/private`. Copying `clusters/public` to `clusters/my-cluster` does not need a matching overlay directory: bootstrap uses `api_visibility` (or `GITOPS_OVERLAY`). Sync policy is automated with **`prune: false`** so Argo cannot uninstall the GitOps operator.

Terraform creates the ESO user-assigned identity and federated credential (trust pinned to `system:serviceaccount:external-secrets-operator:external-secrets-sa` before that account exists). GitOps creates the ServiceAccount without annotations. A Sync Job reads the ConfigMap, stamps `azure.workload.identity/client-id`, and applies `ClusterSecretStore` / `ExternalSecret` because the vault URL is random per cluster and must not live in committed overlays.

Bump a minor by editing the `channel` field in [`gitops/bootstrap/subscription.yaml`](../../gitops/bootstrap/subscription.yaml) (or the other operator Subscriptions) and letting Argo sync. Do not re-run bootstrap for a channel change once GitOps is healthy. Re-run bootstrap only for first install or if the operator / root Application is gone.

GitOps 1.19’s documented OpenShift matrix currently tops out at **4.21**. This repo’s example clusters use **4.22**. If the InstallPlan fails with `maxOpenShiftVersion`, bump `gitops-1.19` to the current `gitops-1.x` line (not `latest`, which can jump minors without a git change).

## Make and env

```bash
make cluster.<name>.bootstrap
```

| Variable | Default | Purpose |
|----------|---------|---------|
| `GITOPS_REPO` | `https://github.com/rh-mobb/aro-hcp.git` | Argo `repoURL` |
| `GITOPS_REVISION` | `main` | Branch, tag, or commit |
| `GITOPS_OVERLAY` | unset | Overlay directory (`public`, `private`, or custom). If unset: `gitops/overlays/<profile>` when that directory exists, otherwise `public` or `private` from `api_visibility`. |
| `GITOPS_DRY_RUN=1` | unset | Print manifests; do not talk to the cluster |
| `KUBECONFIG_PATH` | `.kube/config` | Admin kubeconfig from `make cluster.<name>.kubeconfig` |
| `PULL_SECRET_PATH` | unset | Path to a Red Hat [dockerconfigjson pull secret](https://console.redhat.com/openshift/downloads). On **apply**, Make exports this as `TF_VAR_pull_secret_path` so Terraform writes Key Vault `redhat-pull-secret`. On **bootstrap**, it overrides Key Vault and creates `kube-system/additional-pull-secret`. Do **not** replace `openshift-config/pull-secret` — that is the HostedCluster ACR payload secret. Keep the path set on later applies while Terraform should manage the Key Vault secret; clearing it deletes that secret. |

Feature-branch test (until `gitops/` is on `main`):

```bash
GITOPS_REPO=https://github.com/<you>/aro-hcp.git GITOPS_REVISION=feat/gitops \
  make cluster.<name>.bootstrap
```

The root Application is **not** in the Kustomize overlay so a branch override is not reverted to `main` on the first sync. Changing repo/revision later is another bootstrap (or `oc apply` of the Application). Subscriptions **are** in git and Argo-owned.

## OperatorHub

Software Catalog / Installed Operators still speak OLM Classic, which is why this tree uses `Subscription`s (they show as installed). Do **not** also install the same operators from the catalog — a second Subscription fights the GitOps-managed one.

OLM bundle images come from `registry.redhat.io`. ARO HCP workers only have the service ACR in the HostedCluster pull secret. Add your Red Hat pull secret as **`kube-system/additional-pull-secret`** (`kubernetes.io/dockerconfigjson`). The Hosted Cluster Config Operator merges it and the `global-pull-secret-syncer` DaemonSet writes kubelet config. Original ACR entries win on registry name conflicts; `registry.redhat.io` is not in the original secret, so it is added.

Store the dockerconfigjson in the customer Key Vault (Terraform, when `pull_secret_path` is set). Bootstrap fetches it with the operator’s Azure identity and plants `kube-system/additional-pull-secret` once so OperatorHub can install GitOps and ESO. After that, External Secrets Operator refreshes the same secret from Key Vault (workload identity + `aro-platform-metadata`). Do not patch `openshift-config/pull-secret`. Secrets Store CSI is not used: it mounts into pods rather than kubelet.

OLM v1 `ClusterExtension` is out of scope until the console lists those objects.

## Layout

```text
gitops/
  bootstrap/                 # GitOps operator (script applies this first)
  operators/web-terminal/
  operators/compliance/
  operators/external-secrets/  # RH ESO + metadata Job (no per-cluster IDs in git)
  base/                      # bootstrap + operators
  overlays/public|private    # same baseline today; diverge later
  argocd/root-application.yaml
```

## Permissions

Bootstrap needs a **cluster-admin** kubeconfig (`make cluster.<name>.kubeconfig`) and **Key Vault Secrets User** (or the deployer’s Key Vault Administrator) to `get` `redhat-pull-secret`, unless `kube-system/additional-pull-secret` already exists or `PULL_SECRET_PATH` is set.

## Related

- [Issue #9](https://github.com/rh-mobb/aro-hcp/issues/9)
- [Full-stack deployment](../prerequisites/full-stack.md)
- [Architecture](../architecture.md)

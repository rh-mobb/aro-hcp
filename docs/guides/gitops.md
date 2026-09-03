# GitOps bootstrap

Optional post-deploy path: install **OpenShift GitOps** (Argo CD) and a small cloud-agnostic operator baseline from this repository. Terraform still creates the cluster. This is **not** the [validated-pattern-terraform-rosa](https://github.com/rh-mobb/validated-pattern-terraform-rosa) Helm catalog.

## When to run it

Same Make shape as ROSA validated-pattern (`cluster.<name>.bootstrap`). Repo-root `make bootstrap` is still a deprecated alias for `make setup` (CLI extension) and does **not** install GitOps.

After the cluster is `Succeeded` and you have admin kubeconfig:

```bash
# Example profiles set pull_secret_path = "../tmp/pull-secret.txt" (copy dockerconfigjson there).
# Override with PULL_SECRET_PATH=... if needed; Make exports TF_VAR_pull_secret_path.
make cluster.<name>.apply

make cluster.<name>.kubeconfig
make cluster.<name>.bootstrap
```

`bootstrap` reads Key Vault `redhat-pull-secret` (terraform output `key_vault_name` + `pull_secret_key_vault_secret_name`). You do not need the file on disk at bootstrap time if apply already stored it. `PULL_SECRET_PATH` on bootstrap still overrides Key Vault.

Private API: `make cluster.<name>.sshuttle.connect` before bootstrap so `oc` can reach the API.

External-auth is not required to install operators. It **is** required for a usable **console** (Web Terminal lives there) and for **GitOps web login**. HCP has no in-cluster OAuth server, so the default Argo CD Dex setting (`openShiftOAuth: true`, “Log in via OpenShift”) cannot work. Terraform registers the GitOps `/auth/callback` URI at apply (same Entra app as the console). After GitOps is up, bootstrap patches the operator-created `ArgoCD/openshift-gitops` CR: drop Dex, set `spec.oidcConfig` to the same Entra issuer as console, copy the console client secret into `argocd-secret` (no credential reset), and **restart** `openshift-gitops-server` (Argo CD otherwise keeps querying Dex for OIDC discovery). If you bootstrapped before the console secret exists, re-run bootstrap (or `external-auth`) so that patch runs. Per-cluster client IDs stay out of `gitops/`.

Use a normal browser for GitOps login. An embedded IDE browser often drops the OAuth state cookie on the return from Entra (`http: named cookie not present` → blank page on `/auth/callback`).

## What gets installed

OLM **Classic** `Subscription`s (`installPlanApproval: Automatic`). Channels are pinned in git so a minor bump is a commit; z-stream on that channel can still roll out from the catalog.

| Operator | Namespace | Channel (in git) |
|----------|-----------|------------------|
| OpenShift GitOps | `openshift-gitops-operator` | `gitops-1.19` |
| Web Terminal | `openshift-operators` | `fast` |
| Compliance Operator | `openshift-compliance` | `stable` |
| External Secrets Operator | `external-secrets-operator` | `stable-v1` |

HCP has no master nodes. The Compliance Operator CSV still selects `node-role.kubernetes.io/master`. The Subscription sets `spec.config.nodeSelector` to `node-role.kubernetes.io/worker` (OLM **replaces** the CSV selector) and `PLATFORM=HyperShift`, matching the hosted-control-plane install path. Direct Deployment patches are reverted on the next OLM reconcile.

The GitOps operator creates the default Argo CD instance in `openshift-gitops`. Bootstrap patches **that** CR for Entra OIDC when external-auth already ran (it does not install a second instance). It also publishes ConfigMap `aro-platform-metadata` in that namespace (Terraform outputs: ESO client ID, tenant, Key Vault URI) and plants a root `Application` (`cluster-config`) that syncs `gitops/overlays/public` or `gitops/overlays/private`. Copying `clusters/public` to `clusters/my-cluster` does not need a matching overlay directory: bootstrap uses `api_visibility` (or `GITOPS_OVERLAY`). Sync policy is automated with **`prune: false`** so Argo cannot uninstall the GitOps operator. The Application **ignores ServiceAccount annotation / pull-secret drift** (`RespectIgnoreDifferences`): the default GitOps controller cannot patch ServiceAccounts, and the metadata Job plus OpenShift mutate those fields after create.

Fleet (tenant-specific) desired state — Entra group `cluster-admin`, extra apps — belongs in a **cluster-config repo**, not in this installer. Point Argo at that repo with `GITOPS_REPO` + `GITOPS_SOURCE_ROOT=overlays` (see [Cluster-config repo](#cluster-config-repo)). The signed-in deployer is still bound as OpenShift `cluster-admin` by `make cluster.<name>.external-auth` unless `SKIP_RBAC_USER=1`. GitOps **login** admins are patched on the Argo CD CR at bootstrap (same signed-in UPN), not from overlay YAML.

Terraform creates the ESO user-assigned identity and federated credential (trust pinned to `system:serviceaccount:external-secrets-operator:external-secrets-sa` before that account exists). GitOps creates the ServiceAccount without annotations. A Sync Job reads the ConfigMap, stamps `azure.workload.identity/client-id`, and applies `ClusterSecretStore` / `ExternalSecret` because the vault URL is random per cluster and must not live in committed overlays. The default GitOps controller cannot patch ServiceAccounts or create Jobs; the root Application ignores SA drift, and a Role in `external-secrets-operator` lets the controller run the Sync hook.

Bump a minor by editing the `channel` field in [`gitops/bootstrap/subscription.yaml`](../../gitops/bootstrap/subscription.yaml) (or the other operator Subscriptions) and letting Argo sync. Do not re-run bootstrap for a channel change once GitOps is healthy. Re-run bootstrap for first install, if the operator / root Application is gone, or to apply GitOps Entra OIDC after a later `external-auth`.

GitOps 1.19’s documented OpenShift matrix currently tops out at **4.21**. This repo’s example clusters use **4.22**. If the InstallPlan fails with `maxOpenShiftVersion`, bump `gitops-1.19` to the current `gitops-1.x` line (not `latest`, which can jump minors without a git change).

## Make and env

```bash
make cluster.<name>.bootstrap
```

| Variable | Default | Purpose |
|----------|---------|---------|
| `GITOPS_REPO` | `https://github.com/rh-mobb/validated-pattern-aro-hcp.git` | Argo `repoURL` |
| `GITOPS_REVISION` | `main` | Branch, tag, or commit |
| `GITOPS_SOURCE_ROOT` | `gitops/overlays` | Argo Application path prefix. Use `overlays` with a [cluster-config repo](#cluster-config-repo). |
| `GITOPS_OVERLAY` | unset | Overlay directory (`public`, `private`, or custom). If unset: `gitops/overlays/<profile>` when that directory exists, otherwise `public` or `private` from `api_visibility`. |
| `GITOPS_DRY_RUN=1` | unset | Print manifests; do not talk to the cluster |
| `KUBECONFIG_PATH` | `.kube/config` | Admin kubeconfig from `make cluster.<name>.kubeconfig` |
| `PULL_SECRET_PATH` | unset | Path to a Red Hat [dockerconfigjson pull secret](https://console.redhat.com/openshift/downloads). On **apply**, Make exports this as `TF_VAR_pull_secret_path` so Terraform writes Key Vault `redhat-pull-secret`. On **bootstrap**, it overrides Key Vault and creates `kube-system/additional-pull-secret`. Do **not** replace `openshift-config/pull-secret` — that is the HostedCluster ACR payload secret. Keep the path set on later applies while Terraform should manage the Key Vault secret; clearing it deletes that secret. |

Feature-branch test (until `gitops/` is on `main`):

```bash
GITOPS_REPO=https://github.com/<you>/validated-pattern-aro-hcp.git GITOPS_REVISION=feat/gitops \
  make cluster.<name>.bootstrap
```

The root Application is **not** in the Kustomize overlay so a branch override is not reverted to `main` on the first sync. Changing repo/revision later is another bootstrap (or `oc apply` of the Application). Subscriptions **are** in git and Argo-owned.

## Cluster-config repo

This repository’s `gitops/` tree is the **tenant-neutral** operator baseline. Org policy (who is OpenShift `cluster-admin`, extra Applications) lives in a separate Git repo that Kustomize-includes the baseline as a remote base.

Example overlay (MOBB / Red Hat Zero): [`validated-pattern-aro-hcp-cluster-config`](https://github.com/rh-mobb/validated-pattern-aro-hcp-cluster-config). Local checkout: `references/validated-pattern-aro-hcp-cluster-config` (gitignored).

```bash
GITOPS_REPO=https://github.com/rh-mobb/validated-pattern-aro-hcp-cluster-config.git \
GITOPS_SOURCE_ROOT=overlays \
  make cluster.<name>.bootstrap
```

Argo then syncs `overlays/public` or `overlays/private` in that repo. Each overlay pulls `github.com/rh-mobb/validated-pattern-aro-hcp//gitops/overlays/<name>?ref=main` and adds org YAML (today: Entra group `ClusterRoleBinding`). Do not commit group object IDs into this installer. `make cluster.<name>.external-auth` still sets `groupMembershipClaims=SecurityGroup` so those bindings match tokens.

The signed-in deployer is a **separate** User binding (`entra-cluster-admin`) from create — break-glass until this Application is Healthy, and if Argo is down. Skip it when the group already covers you:

```bash
SKIP_RBAC_USER=1 make cluster.<name>.external-auth
```

See [Who is cluster-admin](external-auth-entra-id.md#who-is-cluster-admin). Do not also pass `GROUP_ID=` if this overlay already owns `entra-cluster-admin-group`.

If the cluster-config repo is private, add it as a GitOps repository credential. Bootstrap still `oc apply -k`s the **local** installer overlay so operators exist before Argo can clone.

Trident / Azure NetApp Files / OpenShift Virtualization is **not** in this `gitops/` tree. That is a sibling stack: `make cluster.<name>.platform` then the virt/storage repo. Use installer profile [`clusters/aro-virt`](../../clusters/aro-virt/) (`make cluster.aro-virt.virt-pool` for Azure Boost D8s_v6 workers).

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
  overlays/public|private|aro-virt    # same operator baseline today; aro-virt is the virt-ready profile name
  argocd/root-application.yaml
```

## Permissions

Bootstrap needs a **cluster-admin** kubeconfig (`make cluster.<name>.kubeconfig`) and **Key Vault Secrets User** (or the deployer’s Key Vault Administrator) to `get` `redhat-pull-secret`, unless `kube-system/additional-pull-secret` already exists or `PULL_SECRET_PATH` is set.

## Related

- [Issue #9](https://github.com/rh-mobb/validated-pattern-aro-hcp/issues/9)
- [Full-stack deployment](../prerequisites/full-stack.md)
- [Architecture](../architecture.md)

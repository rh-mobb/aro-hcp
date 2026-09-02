# Changelog

Notable **committed** changes to this reference deployment.

Entries are added at **commit time** from that commit’s diff. Do not log in-progress, debug, or reverted work.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `modules/entra` — Entra OIDC app, service principal, Key Vault client secret, and AzAPI `externalAuths/entra` as part of `make cluster.<name>.apply` (redirect URIs from cluster DNS)
- `enable_external_auth` (default true) and `oidc_web_redirects` (default RHOAI `rh-ai` `/oauth2/callback`); console, GitOps, and PKCE `http://localhost` are always registered
- `GITOPS_SOURCE_ROOT` so Argo can sync a cluster-config repo (`overlays/public|private`) that Kustomize-includes this installer’s `gitops/` as a remote base ([`validated-pattern-aro-hcp-cluster-config`](https://github.com/rh-mobb/validated-pattern-aro-hcp-cluster-config))
- `SKIP_RBAC_USER=1` on `make cluster.<name>.external-auth` to skip the signed-in user `entra-cluster-admin` binding when a GitOps group binding already covers the operator
- Example `pull_secret_path = "../tmp/pull-secret.txt"` on public/private tfvars (file gitignored)
- `make cluster.<name>.bootstrap` — OpenShift GitOps (`gitops-1.19`), Web Terminal, Compliance Operator, and Red Hat External Secrets Operator from [`gitops/`](gitops/)
- Optional `pull_secret_path` / `PULL_SECRET_PATH` uploads Red Hat dockerconfigjson to Key Vault `redhat-pull-secret`; bootstrap plants `kube-system/additional-pull-secret` for OperatorHub (do not patch `openshift-config/pull-secret`)
- ESO workload identity `${cluster_name}-eso` (not one of the 13 HCP operators) with Key Vault Secrets User and a federated credential on the cluster OIDC issuer; bootstrap publishes `openshift-gitops/aro-platform-metadata` so GitOps can annotate the ServiceAccount without putting per-cluster IDs in git
- GitOps web SSO via the console Entra app: merge GitOps `/auth/callback`, copy the client secret into `argocd-secret`, replace Dex `openShiftOAuth` with `spec.oidcConfig` on the default Argo CD instance, and restart `openshift-gitops-server`
- `make cluster.<profile>.sshuttle.connect` / `sshuttle.disconnect` / `sshuttle.status` — background sshuttle via jump box (`clusters/<profile>/sshuttle.pid`)
- Per-cluster operator layout: `clusters/<profile>/terraform.tfvars`, local state, and `make cluster.<profile>.<operation>` via `Makefile.cluster`
- Terraform modules (`modules/network`, `identities`, `cluster`, `jumpbox`) with root composition in `terraform/`
- Example profiles [`clusters/public`](clusters/public/) and [`clusters/private`](clusters/private/) (public vs private API/ingress + jump box)
- `scripts/private-dns.sh` and `make cluster.<profile>.private-dns` — customer Private DNS for private API/ingress (operator stopgap until platform DNS)
- `make cluster.<profile>.console-secret` — retry console OAuth secret apply (private API + sshuttle)
- MkDocs operator site ([`mkdocs.yml`](mkdocs.yml), GitHub Pages workflow) with prerequisites, quick start, external-auth guide, and Red Hat brand styling
- `hack/versions` — plan-time OpenShift version validation per region

### Changed
- Deployer is Entra app and service-principal **owner** so Graph can add the client secret (`Application.ReadWrite.OwnedBy` cannot manage an ownerless app)
- `make cluster.<name>.external-auth` applies the console secret and CRBs from Key Vault when Terraform owns the app; it does not create or rotate the registration. Entra Graph rights are required at **apply**, not only at external-auth. `external-auth-delete` leaves ARM `externalAuths` and the app for `terraform destroy`
- GitHub / Pages URLs to [`rh-mobb/validated-pattern-aro-hcp`](https://github.com/rh-mobb/validated-pattern-aro-hcp) (`https://rh-mobb.github.io/validated-pattern-aro-hcp/`)
- `make cluster.<name>.external-auth` always sets Entra `groupMembershipClaims=SecurityGroup` so GitOps group `ClusterRoleBinding`s match token object IDs; fleet admins belong in the cluster-config repo, not this installer’s `gitops/`
- Compliance Operator `Subscription` selects `node-role.kubernetes.io/worker` and `PLATFORM=HyperShift` (HCP has no masters)
- Identity inventory is 13 HCP operators plus one ESO workload identity; architecture, full-stack permissions, and README document GitOps bootstrap and Key Vault Secrets User for the GitOps operator
- MkDocs theme: use Material `default` / `slate` palettes (match ROSA validated-pattern docs) instead of custom RHDS token overrides
- `make bootstrap` renamed to `make setup` (`scripts/setup.sh`); `make bootstrap` remains as a deprecated alias
- Scripts read cluster config from Terraform outputs with fallback to `clusters/<profile>/terraform.tfvars`; per-cluster `TF_DATA_DIR`
- `destroy.sh`: correct state path for node-pool state-rm (OCPBUGS-86702); wait and retry when cluster is already deleting in Azure
- `external-auth-delete` warns and continues if `oc` cannot reach private API
- `jump-pub-check` requires `jump_ssh_source_prefix` in tfvars or `TF_VAR_jump_ssh_source_prefix` when jump is enabled
- Architecture and README docs aligned with modular layout and least-privilege permissions per deploy step

### Removed
- `config/cluster.env.example` and monolithic `terraform/*.tf` resources (replaced by modules + per-cluster tfvars)

### Fixed
- `oc login --exec-plugin=oc-oidc` AADSTS7000218: Entra public-client flows + native `http://localhost` so PKCE works without `--client-secret`
- `make cluster.<profile>.kubeconfig` failed with “Cluster public does not exist” when GNU Make exported `CLUSTER_NAME` from the profile name
- `make cluster.<profile>.destroy` skipped node-pool state-rm when `TF_DATA_DIR` pointed at the wrong cluster
- GitOps `cluster-config` selfHeal no longer patches ESO ServiceAccounts (OpenShift dockercfg + workload-identity annotations); Role `argocd-eso-hooks` lets the default controller create the metadata Sync Job

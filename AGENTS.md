# AGENTS.md

Instructions for AI agents working in this repository.

## What this repo is

Customer-side **ARO HCP reference deployment**. Terraform provisions Azure prerequisites (network, Key Vault, 13 managed identities, RBAC) and the HCP cluster plus default node pool via AzAPI. Bash scripts wrap `az aro hcp` for credentials, extra node pools, and external-auth.

This is **not** the Azure/ARO-HCP service codebase. Do not refactor `references/ARO-HCP/` or `references/bennerv-ARO-HCP/` (gitignored clones).

## Source precedence

When sources disagree:

1. **bennerv/ARO-HCP 0.0.2** (`az aro hcp`, API `2026-06-30-preview`) — CLI flags and **RBAC scopes** (CAPI/CCM/ingress/file-csi/image-registry on **VNet**, not subnet).
2. **`references/ARO-HCP/demo/bicep/`** — ARM body shape (etcd KMS, operatorsAuthentication, network defaults).
3. **`references/ARO HCP Hackathon Guide.md`** — regions, quota, troubleshooting, richer Entra/console setup. Stale for RBAC scopes and API version.
4. Service internals in clones — role GUID confirmation only.

## Hard rules

- **Do not** create the cluster via Terraform `local-exec` (AzAPI `azapi_resource` is the cluster path).
- **Do not** copy subnet-scoped CAPI/CCM/ingress RBAC from older Bicep.
- **`make` is the interface:** run `make fmt lint test` before claiming work is done.
- **Docs and changelog:** keep [`docs/architecture.md`](docs/architecture.md) in sync with code; update [`CHANGELOG.md`](CHANGELOG.md) only at commit time (see below).
- **Never commit:** operator `clusters/*/terraform.tfvars` (except committed examples), `clusters/*/infrastructure.tfstate*`, `config/cluster.env`, kubeconfig, Entra secrets, downloaded `*.whl`.
- **Live Azure:** do not `apply` / `destroy` unless the user asked. Follow [Live Azure deployments](#live-azure-deployments).
- **Git:** feature branches only; Conventional Commits; no `Co-authored-by: Cursor` or AI trailers.

## Layout

| Path | Purpose |
|------|---------|
| `modules/network/` | RG, VNet, NSG, worker + integration subnets |
| `modules/identities/` | Key Vault, etcd key, 13 MIs, RBAC |
| `modules/cluster/` | AzAPI HCP cluster + default node pool |
| `modules/jumpbox/` | Optional Fedora jump VM |
| `terraform/` | Thin root: providers, backend, module composition |
| `clusters/<name>/` | Per-cluster `terraform.tfvars` + state |
| `scripts/` | Idempotent wrappers: credentials, external-auth, extra node pools, destroy |
| `docs/` | Operator guides (MkDocs → GitHub Pages): prerequisites, quick start, external-auth, architecture |
| `mkdocs.yml`, `requirements-docs.txt` | Documentation site config and Python deps |
| `docs/architecture.md` | Resultant resources, RBAC scopes, architecture diagrams |
| `docs/prerequisites/full-stack.md` | Least-privilege permissions per `make cluster.<name>.*` target |
| `CHANGELOG.md` | Commit-scoped operator-visible history (not a work journal) |
| `tests/` | `terraform test` + bats |

## Deploy path

```bash
cp -r clusters/public clusters/my-cluster   # edit terraform.tfvars
make setup
make cluster.my-cluster.apply               # terraform apply (cluster + node pool)
make cluster.my-cluster.kubeconfig          # admin creds (24h TTL)
make cluster.my-cluster.external-auth       # Entra + console (required for a usable console)
make cluster.my-cluster.destroy             # reverse teardown (state-rm last pool, then terraform destroy)
```

## Live Azure deployments

Use this when the user asks to create, apply, verify, or destroy a real cluster. `make` is the interface. Cluster create is AzAPI in Terraform, not `az aro hcp cluster create` and not Terraform `local-exec`.

A **deploy / create cluster** request means the full path: preflight → `make cluster.<name>.apply` → `make cluster.<name>.kubeconfig` → `make cluster.<name>.external-auth`. Do not stop after apply and wait. Console is not usable until external-auth (otherwise the console URL shows **“Application is not available”** / HTTP 503). Skip kubeconfig or external-auth only if the user explicitly said apply-only.

Apply is **30–60+ minutes**. Destroy is irreversible for the customer RG. Do not start either until the preflight below is clean **or** the user has chosen how to handle conflicts.

### Preflight (every apply or destroy)

1. **Azure identity.** `az account show` — confirm subscription name/id and user. If missing or unexpected, stop and ask.
2. **`clusters/<name>/terraform.tfvars`.** Must exist (copy from `clusters/public` or `clusters/private`). Treat it as the intended names, region, and versions. Never commit operator copies. `make cluster.<name>.plan` / `apply` / `destroy` pass `-var-file=clusters/<name>/terraform.tfvars` (beats leftover `TF_VAR_*` for keys in the file).
3. **`TF_VAR_*` leftovers — mandatory.** `-var-file` wins for keys in the cluster tfvars. Leftover `TF_VAR_*` that are **not** in the file (tags, CIDRs, disk size, etc.) still reach Terraform. Scripts after apply (`kubeconfig`, `external-auth`, CLI helpers) read **terraform outputs**, then fall back to the cluster tfvars; env overrides still win. `make test` does **not** pass the var-file and unsets mapped `TF_VAR_*` so CI uses Terraform defaults.

   List them:

   ```bash
   env | grep '^TF_VAR_' || true
   ```

   If **any** `TF_VAR_*` is set (including vars not in the cluster tfvars, such as CIDRs or disk size):

   - Print each `TF_VAR_*` next to the corresponding cluster tfvars value (or “not in cluster tfvars”).
   - **Stop and ask the user** which to do:
     - **A.** Unset the `TF_VAR_*` and deploy from the cluster tfvars.
     - **B.** Keep the `TF_VAR_*` and update the cluster tfvars so operators and Terraform match.
     - **C.** Abort.
   - Do not unset, overwrite, or apply until they pick. Do not assume test leftovers are safe to ignore.
4. **OpenShift versions.** `make cluster.<name>.plan` reads ARM `hcpOpenShiftVersions` for `location` and fails if `cluster_version` / `node_pool_version` are not enabled for their channel. Optional `make cluster.<name>.versions` uses `LOCATION` if set, else `location` from the cluster tfvars.
5. **Existing resources.** `az group show` and `az aro hcp cluster show` (using names from cluster tfvars / terraform outputs). Also `terraform -chdir=terraform state list` with `TF_DATA_DIR=clusters/<name>/.terraform`. If a cluster or non-empty state already exists, stop and ask (apply vs destroy vs leave it).
6. **Plan first.** `make cluster.<name>.plan` and summarize create/change/destroy counts. Proceed to `make cluster.<name>.apply` only if the plan matches what the user asked for.

### After apply

- Confirm `az aro hcp cluster show` and `az aro hcp cluster nodepool show` are `Succeeded`.
- Align cluster tfvars `cluster_name` (and related names) with Terraform outputs if the user chose to keep a `TF_VAR_*` override that is not in the var-file.
- Continue with `make cluster.<name>.kubeconfig` then `make cluster.<name>.external-auth` (the latter depends on kubeconfig). Workers `Ready` is not a finished install; ClusterOperator `console` stays degraded until external-auth.
- After external-auth: console secret present, `oc get co console` Available, console URL HTTP 200, `clusterversion` Available. If Entra app registration fails (insufficient privileges), report the error and the [Entra permissions](docs/guides/external-auth-entra-id.md#directory-roles-least-privilege) needed; do not silently skip.

### Destroy

`make cluster.<name>.destroy` state-rms the default node pool (OCPBUGS-86702) then `terraform destroy`. Always confirm subscription, RG, and cluster name with the user first.

### Do not

- Run `terraform test` and `make cluster.<name>.apply` in the same shell without repeating the `TF_VAR_*` check (`terraform test` variables can leak into the environment).
- Mix jumpbox / private-API work into a deploy unless the user asked for that.
- Call `terraform apply` / `destroy` outside Make (that skips `-var-file=clusters/<name>/terraform.tfvars`), or `az group delete` the managed RG.

## Preview API

Targets `2026-06-30-preview` via AzAPI (`hcpOpenShiftClusters` / `nodePools`) and `az aro hcp` for credentials and external-auth.

## Documentation

When a change affects deploy behavior or resultant Azure/Entra/OpenShift resources, update the docs **in the same work**, not later.

- [`docs/index.md`](docs/index.md) — documentation site home (published at [rh-mobb.github.io/aro-hcp](https://rh-mobb.github.io/aro-hcp/)).
- [`docs/prerequisites/account.md`](docs/prerequisites/account.md) — subscription allow-list, RBAC baseline, quotas, tools.
- [`docs/prerequisites/full-stack.md`](docs/prerequisites/full-stack.md) — deployment workflow and [permissions by step](docs/prerequisites/full-stack.md#permissions-by-deployment-step).
- [`docs/guides/external-auth-entra-id.md`](docs/guides/external-auth-entra-id.md) — Entra OIDC, directory roles, consent.
- [`docs/architecture.md`](docs/architecture.md) — resource inventory, diagrams, RBAC scopes, CIDRs, identity counts.
- [`README.md`](README.md) — operator path: prerequisites summary, `make` targets, troubleshooting.
- [`clusters/public/terraform.tfvars`](clusters/public/terraform.tfvars) — if a new required variable or default appears.

Do not leave architecture docs describing the previous identity set, role assignment scopes, network layout, or permission requirements.

## Changelog

[`CHANGELOG.md`](CHANGELOG.md) records **committed** deltas only. It is not a debug log.

- **Do not** edit `CHANGELOG.md` while exploring, debugging, or iterating on uncommitted work.
- **Do** add an entry only when creating a git commit, and only for that commit’s diff (`git diff --cached` against `HEAD`).
- Describe operator-visible changes (resources, flags, permissions, deploy/teardown steps). Omit `chore` / `test` / `style` with no operator impact.
- Never record tried-and-reverted steps. The bullets must match what the commit actually introduces.

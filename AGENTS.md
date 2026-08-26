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
- **Never commit:** `config/cluster.env`, `*.tfstate*`, kubeconfig, Entra secrets, downloaded `*.whl`.
- **Live Azure:** do not `apply` / `destroy` unless the user asked. Follow [Live Azure deployments](#live-azure-deployments).
- **Git:** feature branches only; Conventional Commits; no `Co-authored-by: Cursor` or AI trailers.

## Layout

| Path | Purpose |
|------|---------|
| `terraform/` | Azure prereqs + HCP cluster and default node pool (AzAPI) |
| `scripts/` | Idempotent wrappers: credentials, external-auth, extra node pools, destroy |
| `config/cluster.env` | Local config (copy from `.example`) |
| `docs/architecture.md` | Resultant resources, permissions, architecture diagrams |
| `CHANGELOG.md` | Commit-scoped operator-visible history (not a work journal) |
| `tests/` | `terraform test` + bats |

## Deploy path

```bash
cp config/cluster.env.example config/cluster.env   # edit values
make all                                           # bootstrap → terraform apply (cluster + node pool)
make kubeconfig                                    # admin creds (24h TTL)
make external-auth                                 # Entra + console (required for a usable console)
make destroy                                       # reverse teardown (state-rm last pool, then terraform destroy)
```

## Live Azure deployments

Use this when the user asks to create, apply, verify, or destroy a real cluster. `make` is the interface. Cluster create is AzAPI in Terraform, not `az aro hcp cluster create` and not Terraform `local-exec`.

A **deploy / create cluster** request means the full path: preflight → `make all` (or `make apply`) → `make kubeconfig` → `make external-auth`. Do not stop after apply and wait. Console is not usable until external-auth (otherwise the console URL shows **“Application is not available”** / HTTP 503). Skip kubeconfig or external-auth only if the user explicitly said apply-only.

Apply is **30–60+ minutes**. Destroy is irreversible for the customer RG. Do not start either until the preflight below is clean **or** the user has chosen how to handle conflicts.

### Preflight (every apply or destroy)

1. **Azure identity.** `az account show` — confirm subscription name/id and user. If missing or unexpected, stop and ask.
2. **`config/cluster.env`.** Must exist (copy from `.example`). Treat it as the intended names, region, and versions. Never commit it.
3. **`TF_VAR_*` overrides — mandatory.** The Makefile assigns with `?=`, so an exported `TF_VAR_*` **wins over** `cluster.env`. Scripts (`kubeconfig`, `external-auth`, CLI helpers) **source `cluster.env`**, so they ignore `TF_VAR_*`. A leftover `TF_VAR_cluster_name` from `terraform test`, a prior shell, or the agent environment will create a cluster whose name does not match `CLUSTER_NAME`, and later `make kubeconfig` will fail.

   List them:

   ```bash
   env | grep '^TF_VAR_' || true
   ```

   If **any** `TF_VAR_*` is set (including vars the Makefile does not map, such as CIDRs or disk size):

   - Print each `TF_VAR_*` next to the corresponding `cluster.env` value (or “not in cluster.env”).
   - **Stop and ask the user** which to do:
     - **A.** Unset the `TF_VAR_*` and deploy from `cluster.env`.
     - **B.** Keep the `TF_VAR_*` and update `cluster.env` so scripts match Terraform.
     - **C.** Abort.
   - Do not unset, overwrite, or apply until they pick. Do not assume test leftovers are safe to ignore.
4. **OpenShift versions.** `make versions` for `LOCATION`. If `NODEPOOL_VERSION` / `CLUSTER_VERSION` is not in that list (patch versions move), stop and ask whether to bump `cluster.env` (gitignored) to the listed version.
5. **Existing resources.** `az group show -n "$RESOURCE_GROUP"` and `az aro hcp cluster show` (using the **resolved** names after step 3). Also `terraform -chdir=terraform state list`. If a cluster or non-empty state already exists, stop and ask (apply vs destroy vs leave it).
6. **Plan first.** `make plan` and summarize create/change/destroy counts and the cluster / node-pool names. Proceed to `make apply` only if the plan matches what the user asked for.

### After apply

- Confirm `az aro hcp cluster show` and `az aro hcp cluster nodepool show` are `Succeeded`.
- Align `cluster.env` `CLUSTER_NAME` (and related names) with Terraform outputs if the user chose to keep a `TF_VAR_*` override.
- Continue with `make kubeconfig` then `make external-auth` (the latter depends on kubeconfig). Workers `Ready` is not a finished install; ClusterOperator `console` stays degraded until external-auth.
- After external-auth: console secret present, `oc get co console` Available, console URL HTTP 200, `clusterversion` Available. If Entra app registration fails (insufficient privileges), report the error and the [operator permissions](docs/architecture.md#operator-permissions) needed; do not silently skip.

### Destroy

`make destroy` state-rms the default node pool (OCPBUGS-86702) then `terraform destroy`. Always confirm subscription, RG, and cluster name with the user first. Do not destroy because a plan looked wrong or a create failed partway unless they said to tear it down.

### Do not

- Run `terraform test` and `make apply` in the same shell without repeating the `TF_VAR_*` check (`terraform test` variables can leak into the environment).
- Mix jumpbox / private-API work into a deploy unless the user asked for that.
- Call `terraform apply` / `destroy` outside Make (that skips `cluster.env` → `TF_VAR_*` wiring), or `az group delete` the managed RG.

## Preview API

Targets `2026-06-30-preview` via AzAPI (`hcpOpenShiftClusters` / `nodePools`) and `az aro hcp` for credentials and external-auth.

## Documentation

When a change affects deploy behavior or resultant Azure/Entra/OpenShift resources, update the docs **in the same work**, not later.

- [`docs/architecture.md`](docs/architecture.md) — resource inventory, diagrams, RBAC scopes, CIDRs, CLI flags, identity counts, and [operator permissions](docs/architecture.md#operator-permissions).
- [`README.md`](README.md) — operator path: prerequisites, `make` targets, troubleshooting.
- [`config/cluster.env.example`](config/cluster.env.example) — if a new required variable or default appears.

Do not leave architecture docs describing the previous identity set, role assignment scopes, network layout, or permission requirements.

## Changelog

[`CHANGELOG.md`](CHANGELOG.md) records **committed** deltas only. It is not a debug log.

- **Do not** edit `CHANGELOG.md` while exploring, debugging, or iterating on uncommitted work.
- **Do** add an entry only when creating a git commit, and only for that commit’s diff (`git diff --cached` against `HEAD`).
- Describe operator-visible changes (resources, flags, permissions, deploy/teardown steps). Omit `chore` / `test` / `style` with no operator impact.
- Never record tried-and-reverted steps. The bullets must match what the commit actually introduces.

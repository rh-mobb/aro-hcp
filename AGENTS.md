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
make external-auth                                 # optional Entra + console
make destroy                                       # reverse teardown (state-rm last pool, then terraform destroy)
```

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

# Prerequisites — Choose Your Path

Before deploying an ARO HCP cluster from this repository, confirm **subscription enrollment**, **Azure RBAC**, and (for a usable console) **Entra directory** rights.

## One deployment path today

This reference implements **full-stack deployment**: one platform team runs Terraform for network, identities, cluster, and default node pool, then optional bash wrappers for credentials and external-auth.

| Layer | Scope | Document |
|-------|-------|----------|
| **0 — Account** | Subscription allow-list, RBAC baseline, quotas, tools | [Account prerequisites](account.md) |
| **1 — Full-stack** | `clusters/<name>/terraform.tfvars` + `make cluster.<name>.*` | [Full-stack deployment](full-stack.md) |
| **2 — Console OIDC** | Entra app + external-auth (after kubeconfig) | [External auth with Entra ID](../guides/external-auth-entra-id.md) |

Bring-your-own network or identities (pre-provisioned VNet, separate security team) is not a first-class module split in this repo. If you reuse existing Azure objects, extend RBAC at those scopes — see [Account prerequisites — scope](account.md#rbac-scope-and-least-privilege).

## Decision flow

```mermaid
flowchart TD
  Start[Start deployment planning]
  Start --> Account[Layer 0: Account prerequisites]
  Account --> Profile[Copy clusters/public or clusters/private]
  Profile --> Init[make cluster.name.init / plan]
  Init --> Apply[make cluster.name.apply]
  Apply --> Kube[make cluster.name.kubeconfig]
  Kube --> Auth[make cluster.name.external-auth]
  Auth --> Done[Console Available]

  Profile --> Private{Private API or ingress?}
  Private -->|Yes| Jump[make cluster.name.jump-key then jump]
  Jump --> Apply
```

## Related

- [Quick start](../getting-started/quick-start.md) — minimal command sequence
- [Architecture](../architecture.md) — resource inventory and service identity RBAC
- [Cluster configurations](../../clusters/README.md) — example `terraform.tfvars`

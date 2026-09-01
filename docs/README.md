# Documentation

Published site: [https://rh-mobb.github.io/aro-hcp/](https://rh-mobb.github.io/aro-hcp/) (MkDocs Material, deployed from `main` via GitHub Actions). Local preview: `make docs-preview`.

Site home: [index.md](index.md). Start with [Prerequisites](prerequisites/index.md), then follow [Quick start](getting-started/quick-start.md).

| Document | Purpose |
|----------|---------|
| [Prerequisites — choose your path](prerequisites/index.md) | Account setup and deployment layers |
| [Account prerequisites](prerequisites/account.md) | Subscription allow-list, Azure RBAC baseline, quotas, tools |
| [Full-stack deployment](prerequisites/full-stack.md) | Workflow and **least-privilege permissions per `make` target** |
| [Quick start](getting-started/quick-start.md) | Deploy the `clusters/public` example |
| [External auth with Entra ID](guides/external-auth-entra-id.md) | Console OIDC, directory roles, consent, RBAC |
| [GitOps bootstrap](guides/gitops.md) | Optional OpenShift GitOps + operator baseline |
| [Architecture](architecture.md) | Resultant Azure/Entra/OpenShift resources, RBAC scopes, diagrams |

## Permission model (summary)

Three independent planes:

1. **Azure RBAC** — Terraform and `az aro hcp` against the subscription or customer resource group.
2. **Microsoft Entra ID** — App registration for console OIDC (`make cluster.<name>.external-auth` only).
3. **OpenShift RBAC** — Admin kubeconfig (24h) to apply the console secret and optional `ClusterRoleBinding`.

Azure **Owner** or **Contributor + User Access Administrator** on the customer RG is the usual minimum for `make cluster.<name>.apply`. Entra **Application Administrator is not required** when users may register applications, or when the operator holds **Application Developer**. Details: [Full-stack deployment — permissions by step](prerequisites/full-stack.md#permissions-by-deployment-step).

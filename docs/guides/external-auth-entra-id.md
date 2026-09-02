# External Authentication with Microsoft Entra ID

Configure ARO HCP console and CLI OIDC using Microsoft Entra ID. This repository automates the flow with `make cluster.<name>.external-auth` ([`scripts/external-auth.sh`](../../scripts/external-auth.sh)).

**Console is not usable until external-auth completes** — without it, the console URL returns “Application is not available” and ClusterOperator `console` stays degraded.

## Architecture

```mermaid
graph TB
    subgraph Entra["Microsoft Entra ID"]
        AR[App registration]
        TE[Token endpoint]
    end

    subgraph ARO["ARO HCP cluster"]
        EA[externalAuths/entra ARM child]
        CON[Console — OIDC relying party]
        API[Kubernetes API — OIDC validation]
    end

    U[User browser] --> CON
    CON --> AR
    U --> AR
    AR --> TE
    CON --> API
    Kube[Admin kubeconfig] -.->|console secret| CON

    style Entra fill:#0078d4,color:#fff
    style ARO fill:#ee0000,color:#fff
```

The script:

1. Creates or updates an Entra app registration. Redirect URIs are **merged**: console `/auth/callback`, `http://localhost:8000`, and GitOps `/auth/callback` when the `openshift-gitops-server` route exists. A re-run does not drop a GitOps URI. Enables **public client flows** (`isFallbackPublicClient`) and native redirect `http://localhost` so `oc login --exec-plugin=oc-oidc` can complete Auth Code + PKCE on a random localhost port (the console client secret stays for the confidential console/GitOps clients).
2. Resets a client secret for the confidential console client (create path only — GitOps SSO copies this secret and must not reset it again).
3. Calls `az aro hcp cluster external-auth create` (issuer, audience, username claim, groups claim, console + CLI clients).
4. Applies the console client secret to `openshift-config` using the **24h admin kubeconfig**.
5. OpenShift `cluster-admin` — two different bindings; see [Who is cluster-admin](#who-is-cluster-admin). Create binds the signed-in Entra user unless `SKIP_RBAC_USER=1`. Sets `groupMembershipClaims=SecurityGroup` so GitOps group bindings can match token object IDs.
6. If the default Argo CD instance is already installed, patches it for Entra OIDC (same app). Otherwise `make cluster.<name>.bootstrap` does that patch after GitOps is up.

Run `make cluster.<name>.kubeconfig` before `external-auth`.

## Prerequisites by plane

| Plane | Requirement | Notes |
|-------|-------------|-------|
| Azure RBAC | **Contributor** on `hcpOpenShiftClusters` (or customer RG) | PUT `externalAuths` child resource |
| Entra ID | App registration rights — see [Directory roles](#directory-roles-least-privilege) | Separate from Azure subscription Owner |
| OpenShift | Admin **kubeconfig** (from `make cluster.<name>.kubeconfig`) | Applies secret in `openshift-config`; TTL 24h |
| Tools | `az`, `oc`, `jq` | `oc` >= 4.20 with `oc-oidc` for `login` subcommand |

## Directory roles (least privilege)

The script uses Azure CLI Microsoft Graph delegated permissions (`az ad app create`, `az ad sp create`, `az ad app update`, `az ad app credential reset`, optional `az ad app delete`).

**You do not need Global Administrator.** You do **not** always need Application Administrator.

| Tenant setting | What the operator needs |
|----------------|-------------------------|
| Entra ID → Users → User settings → **Users can register applications** = **Yes** (common default) | No directory admin role. Operator creates the app, becomes **owner**, manages secrets and redirect URIs. |
| That setting = **No** (locked-down enterprise) | **Application Developer** — creates apps the operator owns when user registration is disabled. Broader: **Cloud Application Administrator** or **Application Administrator** (tenant-wide app management — treat as privileged). |

[Application Developer](https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference#application-developer) is Microsoft’s documented least-privilege role when user app registration is disabled.

[Cloud Application Administrator](https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference#cloud-application-administrator) can manage all enterprise apps — more power than this script requires.

### What the default script does **not** require

| Not required | Why |
|--------------|-----|
| Application Administrator | No tenant-wide app management |
| Microsoft Graph **application** permissions on the OIDC app | Uses `preferred_username`, not Graph `email` claim |
| Tenant admin consent for Graph on the cluster app | No `az ad app permission add` / admin consent flow |
| Global Administrator | Directory roles above suffice |

### Azure CLI Graph consent

`az ad *` uses Microsoft Graph as the signed-in user (typically `Application.ReadWrite.All` delegated). First run may prompt consent. If the tenant disables user consent, a **Cloud Application Administrator** (or Global Administrator) must grant admin consent to **Azure CLI** for those Graph scopes — that is consent for the CLI tool, not for the cluster OIDC app.

### Admin-created app (split responsibility)

If an identity admin creates the app:

1. Admin creates app registration and adds the operator as **owner**.
2. Operator sets `CLIENT_ID` in `.external-auth/state.env` or re-runs create (script reuses stored `CLIENT_ID`).
3. Operator still needs owner (or Application Developer) for `az ad app credential reset`.

## Run external-auth

```bash
make cluster.<name>.kubeconfig
make cluster.<name>.external-auth
```

Environment (optional overrides via terraform outputs / tfvars):

| Variable | Default source |
|----------|----------------|
| `EXTERNAL_AUTH_NAME` | `entra` |
| `APP_DISPLAY_NAME` | `<cluster_name>-console` |

State file: `.external-auth/state.env` (gitignored) — stores `CLIENT_ID` for idempotent re-runs.

### Subcommands

| Command | Azure | Entra | OpenShift |
|---------|-------|-------|-----------|
| `create` (default via make) | Contributor on cluster | App + SP + secret | Admin kubeconfig — console secret; `entra-cluster-admin` for the signed-in user unless `SKIP_RBAC_USER=1` |
| `show` | Reader on cluster | None | None |
| `delete` (via `external-auth-delete`) | Contributor on cluster | Delete app (owner or elevated role) | Optional — delete console secret |
| `rbac-user` | None | `az ad signed-in-user show` | Admin kubeconfig — `ClusterRoleBinding` `entra-cluster-admin` (also run from create unless `SKIP_RBAC_USER=1`) |
| `rbac-group` | None | Optional `groupMembershipClaims` on app | Admin kubeconfig — `GROUP_ID=` required; binding `entra-cluster-admin-group` (also run from create when `GROUP_ID` is set) |
| `login` | None | Browser PKCE (`oc-oidc`) | OIDC login |

## Who is cluster-admin

Entra login is **authentication**. OpenShift `cluster-admin` is a **separate** `ClusterRoleBinding`. Do not mix these two bindings, and do not put either in this installer’s `gitops/` tree.

| Binding | Name | Subject | Source of truth | When you need it |
|---------|------|---------|-----------------|------------------|
| Deployer (break-glass) | `entra-cluster-admin` | **User** — signed-in UPN (`az ad signed-in-user`) | `make cluster.<name>.external-auth` | Console/`oc` Entra login **before** GitOps has synced, and if Argo is down. You are not “the fleet admin list.” |
| Fleet admins | `entra-cluster-admin-group` | **Group** — Entra security group object ID | [Cluster-config repo](gitops.md#cluster-config-repo) (preferred), or `GROUP_ID=` / `rbac-group` once | Same admins on every cluster. Add people in Entra, not YAML. |

Default create applies the **user** binding so the person who just stood the cluster up is not 403 until Argo syncs. Skip it when the cluster-config group already covers you (or you only use the 24h kubeconfig until GitOps is Healthy):

```bash
SKIP_RBAC_USER=1 make cluster.<name>.external-auth
```

Do not also pass `GROUP_ID=` if GitOps already owns `entra-cluster-admin-group` — two writers on the same object. One-shot without GitOps:

```bash
GROUP_ID=<object-id> make cluster.<name>.external-auth
# or later (does not rotate the console secret):
GROUP_ID=<object-id> bash scripts/external-auth.sh rbac-group
```

Looking up group IDs may require **Group Reader** or **Directory Reader** in locked-down tenants.

## First login and user consent

Users authenticating to the console or `oc login --exec-plugin=oc-oidc` may see “Permissions requested” for OpenID / `profile`. If user consent is allowed, they accept individually. If user consent is disabled, an admin consents to **this** app for the tenant (still not Application Administrator if another owner created the app).

## Typical failures

| Error | Cause | Fix |
|-------|-------|-----|
| `Authorization_RequestDenied` on `az ad app create` / `credential reset` | User app registration disabled; no Application Developer | Assign Application Developer or have admin create app + add you as owner |
| `AADSTS7000218` `client_assertion` or `client_secret` | `oc-oidc` PKCE against a confidential-only app (secret present, public client flows off) | Re-run `make cluster.<name>.external-auth` (script sets `isFallbackPublicClient` and native `http://localhost`). Do not pass `--client-secret` on the CLI. |
| Console 503 / “Application is not available” | External-auth not run or secret missing | Re-run `make cluster.<name>.external-auth` after fresh kubeconfig |
| Invalid redirect URI | Console URL changed or wrong callback | Re-run create — script **merges** redirect URIs from live console URL (and GitOps route if present) |
| GitOps “Log in via OpenShift” / Dex connection refused | Default Dex uses in-cluster OAuth, which HCP does not have | Run external-auth then bootstrap; GitOps login is **Microsoft Entra ID**, not OpenShift OAuth |
| GitOps `/auth/callback` blank | Missing OAuth state cookie or server still querying Dex after the SSO switch | Use a normal browser (not an IDE webview). Bootstrap restarts `openshift-gitops-server` after the OIDC patch. |
| Secret step skipped | No kubeconfig at external-auth time | `make cluster.<name>.kubeconfig` then re-run external-auth |

## Delete external auth

```bash
make cluster.<name>.external-auth-delete
```

Removes ARM `externalAuths`, console secret (if kubeconfig present), and Entra app (if state file exists). Deleting the Entra app requires app **owner** or directory role with delete rights — subscription Owner is insufficient.

## Related

- [Full-stack — permissions by step](../prerequisites/full-stack.md#permissions-by-deployment-step)
- [Architecture — operator permissions](../architecture.md#operator-permissions)
- [Architecture — credentials and optional Entra](../architecture.md#credentials-and-optional-entra)

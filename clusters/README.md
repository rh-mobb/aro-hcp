# Cluster configurations

Before first deploy, complete [Account prerequisites](../docs/prerequisites/account.md) and review [permissions by step](../docs/prerequisites/full-stack.md#permissions-by-deployment-step).

Each directory under `clusters/` represents one ARO HCP deployment. Example profiles:

| Directory | Profile |
|-----------|---------|
| [`public/`](public/) | Public API and ingress; no jump box |
| [`private/`](private/) | Private API and ingress; jump box enabled |

## Usage

```bash
# Edit the example tfvars or copy a directory for your cluster
cp -r clusters/public clusters/my-cluster
# edit clusters/my-cluster/terraform.tfvars

make cluster.my-cluster.init
make cluster.my-cluster.plan
make cluster.my-cluster.apply
make cluster.my-cluster.kubeconfig
make cluster.my-cluster.external-auth
```

When `enable_jumpbox = true`:

```bash
make cluster.private.jump-key   # writes clusters/private/jump + jump.pub
# jump_ssh_source_prefix in terraform.tfvars or TF_VAR_jump_ssh_source_prefix (your /32)
make cluster.private.apply
make cluster.private.sshuttle.connect  # or jump (print foreground command)
make cluster.private.kubeconfig
make cluster.private.private-dns # customer Private DNS zone in the cluster RG
make cluster.private.external-auth
```

`make cluster.<profile>.destroy` runs `private-dns-delete` automatically when `api_visibility = "Private"`.

## State and secrets

Per cluster (gitignored for operator dirs):

- `infrastructure.tfstate` — Terraform state (`terraform init -backend-config=...`)
- `.terraform/` — provider cache (`TF_DATA_DIR`)
- `jump` / `jump.pub` — SSH keypair for the jump VM (when enabled)

Never commit state files, private keys, or kubeconfig.

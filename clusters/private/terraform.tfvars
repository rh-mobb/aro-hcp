# Private API + ingress example with optional jump box for sshuttle access.

location     = "uksouth"
cluster_name = "my-private-cluster"

cluster_version = "4.22"
cluster_channel = "stable"

node_pool_version = "4.22.9"
node_pool_channel = "stable"

node_pools = {
  np-1 = {
    vm_size           = "Standard_D4s_v6"
    replicas          = 2
    availability_zone = "1"
  }
}

api_visibility     = "Private"
ingress_visibility = "Private"

enable_jumpbox = true
# Required when enable_jumpbox is true. SSH 22 from this CIDR only (use your /32).
# jump_ssh_source_prefix = "1.2.3.4/32"

# Reserved CIDR for a sibling ANF delegated subnet (not created here). Default 10.0.3.0/24.
# netapp_subnet_prefix = "10.0.3.0/24"

# Red Hat pull secret for OperatorHub (GitOps bootstrap). Relative paths are
# resolved from terraform/. The file is gitignored (tmp/ and pull-secret.txt).
pull_secret_path = "../tmp/pull-secret.txt"
# oidc_web_redirects = {}   # extra Entra Web callbacks; console + GitOps + PKCE always on

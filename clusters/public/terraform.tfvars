# Operator config for Terraform. Copy to clusters/<name>/terraform.tfvars (gitignored except examples).
# make cluster.<name>.plan/apply/destroy pass this file with -var-file.

location     = "uksouth"
cluster_name = "my-cluster"

# Optional. Omit to derive from cluster_name:
#   resource_group_name          = "<cluster_name>-rg"
#   managed_resource_group_name  = "<cluster_name>-managed"
#   vnet_name                    = "<cluster_name>-vnet"
#   subnet_name                  = "<cluster_name>-worker"
#   vnet_integration_subnet_name = "<cluster_name>-integration"
#   nsg_name                     = "<cluster_name>-nsg"

# Cluster stream (X.Y). Plan fails if this stream is not enabled in location.
cluster_version = "4.22"
cluster_channel = "stable"

# Default node pool
node_pool_name     = "np-1"
node_pool_replicas = 2
node_pool_vm_size  = "Standard_D4s_v6"
node_pool_version  = "4.22.9"
node_pool_channel  = "stable"

# Create-time only; cannot change in place.
api_visibility     = "Public"
ingress_visibility = "Public"

# Optional Fedora jump VM + public IP for sshuttle into the VNet.
enable_jumpbox = false
# Required when enable_jumpbox is true. SSH 22 from this CIDR only (use your /32).
# jump_ssh_source_prefix = "1.2.3.4/32"

# Reserved CIDR for a sibling ANF delegated subnet (not created here). Default 10.0.3.0/24.
# Must not overlap worker 10.0.0.0/24, integration 10.0.1.0/24, or jump 10.0.2.0/28.
# netapp_subnet_prefix = "10.0.3.0/24"

# Red Hat pull secret for OperatorHub (GitOps bootstrap). Relative paths are
# resolved from terraform/. The file is gitignored (tmp/ and pull-secret.txt).
pull_secret_path = "../tmp/pull-secret.txt"
# pull_secret_key_vault_secret_name = "redhat-pull-secret"

# Entra OIDC (Terraform). Console, GitOps, and PKCE http://localhost are always
# registered after cluster DNS is known. Extra Web callbacks (host + path):
# oidc_web_redirects = {}
# oidc_web_redirects = {
#   rhoai = { host = "rh-ai", path = "/oauth2/callback" }  # default
# }
# enable_external_auth = false

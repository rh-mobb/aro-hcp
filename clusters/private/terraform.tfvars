# Private API + ingress example with optional jump box for sshuttle access.

location     = "uksouth"
cluster_name = "my-private-cluster"

cluster_version = "4.22"
cluster_channel = "stable"

node_pool_name     = "np-1"
node_pool_replicas = 2
node_pool_vm_size  = "Standard_D4s_v6"
node_pool_version  = "4.22.9"
node_pool_channel  = "stable"

api_visibility     = "Private"
ingress_visibility = "Private"

enable_jumpbox = true
# Required when enable_jumpbox is true. SSH 22 from this CIDR only (use your /32).
# jump_ssh_source_prefix = "1.2.3.4/32"

# Optional Red Hat pull secret for OperatorHub (GitOps bootstrap). Prefer
# PULL_SECRET_PATH=~/pull-secret.txt make cluster.<name>.apply  (never commit the file).
# pull_secret_path = "/absolute/path/to/pull-secret.txt"

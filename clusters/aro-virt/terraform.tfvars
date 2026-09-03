# Full-stack example: ARO HCP + reserved ANF CIDR + OpenShift Virtualization workers.
# Operator config for Terraform. Copy to clusters/<name>/terraform.tfvars (gitignored except examples).
# make cluster.<name>.plan/apply/destroy pass this file with -var-file.
#
# Path:
#   make cluster.aro-virt.apply
#   make cluster.aro-virt.kubeconfig
#   make cluster.aro-virt.external-auth
#   make cluster.aro-virt.bootstrap
#   make cluster.aro-virt.virt-pool          # Azure Boost Dsv6, 8+ cores (required for CNV)
#   make cluster.aro-virt.platform
#   # sibling validated-pattern-openshift-virt:
#   ARO_HCP_ROOT=… ARO_HCP_PROFILE=aro-virt make cluster.aro-virt.apply
#   make cluster.aro-virt.bootstrap          # Trident + kubevirt-hyperconverged
#
# Cluster-config repo (org group cluster-admin): GITOPS_REPO=…cluster-config.git
# GITOPS_SOURCE_ROOT=overlays make cluster.aro-virt.bootstrap

location     = "uksouth"
cluster_name = "aro-virt"

cluster_version = "4.22"
cluster_channel = "stable"

# Platform / operator workers (not a supported CNV SKU — 8+ core Dsv5/Dsv6 required).
node_pool_name     = "np-1"
node_pool_replicas = 2
node_pool_vm_size  = "Standard_D4s_v6"
node_pool_version  = "4.22.9"
node_pool_channel  = "stable"

api_visibility     = "Public"
ingress_visibility = "Public"

enable_jumpbox = false

# Reserved CIDR for sibling ANF delegated subnet (not created here).
# netapp_subnet_prefix = "10.0.3.0/24"

# Extra virt pool is CLI, not Terraform: make cluster.aro-virt.virt-pool
# Default: NAME=np-virt VM_SIZE=Standard_D8s_v6 REPLICAS=2
# label workload=virtualization. Quota: +16 vCPU Standard Dsv6.

pull_secret_path = "../tmp/pull-secret.txt"

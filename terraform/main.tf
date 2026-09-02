module "network" {
  source = "../modules/network"

  location                       = var.location
  cluster_name                   = var.cluster_name
  resource_group_name            = var.resource_group_name
  vnet_name                      = var.vnet_name
  subnet_name                    = var.subnet_name
  vnet_integration_subnet_name   = var.vnet_integration_subnet_name
  nsg_name                       = var.nsg_name
  address_prefix                 = var.address_prefix
  subnet_prefix                  = var.subnet_prefix
  vnet_integration_subnet_prefix = var.vnet_integration_subnet_prefix
  tags                           = var.tags
}

module "identities" {
  source = "../modules/identities"

  cluster_name                      = var.cluster_name
  resource_group_name               = module.network.resource_group_name
  location                          = module.network.location
  vnet_id                           = module.network.vnet_id
  nsg_id                            = module.network.nsg_id
  subnet_id                         = module.network.worker_subnet_id
  tags                              = var.tags
  pull_secret_content               = length(trimspace(var.pull_secret_path)) > 0 ? file(var.pull_secret_path) : ""
  pull_secret_key_vault_secret_name = var.pull_secret_key_vault_secret_name
}

module "cluster" {
  source = "../modules/cluster"

  cluster_name                        = var.cluster_name
  resource_group_name                 = module.network.resource_group_name
  resource_group_id                   = module.network.resource_group_id
  location                            = module.network.location
  managed_resource_group_name         = var.managed_resource_group_name
  address_prefix                      = module.network.address_prefix
  worker_subnet_id                    = module.network.worker_subnet_id
  vnet_integration_subnet_id          = module.network.vnet_integration_subnet_id
  nsg_id                              = module.network.nsg_id
  key_vault_name                      = module.identities.key_vault_name
  etcd_key_version                    = module.identities.etcd_key_version
  etcd_encryption_key_name            = module.identities.etcd_encryption_key_name
  service_identity_id                 = module.identities.service_identity_id
  control_plane_operators             = module.identities.control_plane_operators
  data_plane_operators                = module.identities.data_plane_operators
  cluster_identity_ids                = module.identities.cluster_identity_ids
  cluster_version                     = var.cluster_version
  cluster_channel                     = var.cluster_channel
  api_visibility                      = var.api_visibility
  ingress_visibility                  = var.ingress_visibility
  outbound_type                       = var.outbound_type
  cluster_image_registry_state        = var.cluster_image_registry_state
  vault_visibility                    = var.vault_visibility
  pod_cidr                            = var.pod_cidr
  service_cidr                        = var.service_cidr
  host_prefix                         = var.host_prefix
  node_pool_name                      = var.node_pool_name
  node_pool_vm_size                   = var.node_pool_vm_size
  node_pool_disk_size_gib             = var.node_pool_disk_size_gib
  node_pool_disk_storage_account_type = var.node_pool_disk_storage_account_type
  node_pool_replicas                  = var.node_pool_replicas
  node_pool_version                   = var.node_pool_version
  node_pool_channel                   = var.node_pool_channel
  tags                                = var.tags

  depends_on = [module.identities]
}

module "entra" {
  count  = var.enable_external_auth ? 1 : 0
  source = "../modules/entra"

  cluster_name           = var.cluster_name
  cluster_id             = module.cluster.cluster_id
  console_url            = coalesce(module.cluster.console_url, "")
  dns_base_domain        = coalesce(module.cluster.dns_base_domain, "")
  dns_base_domain_prefix = coalesce(module.cluster.dns_base_domain_prefix, "")
  tenant_id              = module.identities.tenant_id
  key_vault_id           = module.identities.key_vault_id
  oidc_web_redirects     = var.oidc_web_redirects

  depends_on = [module.cluster, module.identities]
}

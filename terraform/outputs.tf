output "cluster_name" {
  value = var.cluster_name
}

output "resource_group_name" {
  value = module.network.resource_group_name
}

output "location" {
  value = module.network.location
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "subnet_id" {
  value = module.network.worker_subnet_id
}

output "vnet_integration_subnet_id" {
  value = module.network.vnet_integration_subnet_id
}

output "nsg_id" {
  value = module.network.nsg_id
}

output "vnet_id" {
  value = module.network.vnet_id
}

output "key_vault_name" {
  value = module.identities.key_vault_name
}

output "key_vault_id" {
  value = module.identities.key_vault_id
}

output "key_vault_uri" {
  value = module.identities.key_vault_uri
}

output "tenant_id" {
  value = module.identities.tenant_id
}

output "eso_identity_id" {
  description = "Resource ID of the ESO workload identity (not an HCP cluster identity)."
  value       = module.identities.eso_identity_id
}

output "eso_client_id" {
  description = "Client ID published to openshift-gitops/aro-platform-metadata for the GitOps annotation Job."
  value       = module.identities.eso_client_id
}

output "oidc_issuer_url" {
  description = "Cluster OIDC issuer used by the ESO federated identity credential."
  value       = module.cluster.oidc_issuer_url
}

output "etcd_key_version" {
  value = module.identities.etcd_key_version
}

output "pull_secret_key_vault_secret_name" {
  description = "Key Vault secret name for the Red Hat pull secret. Bootstrap reads this secret; the value is never exported."
  value       = module.identities.pull_secret_key_vault_secret_name
}

output "identity_ids" {
  description = "User-assigned identity resource IDs keyed by operator name."
  value       = module.identities.identity_ids
}

output "role_assignment_count" {
  value = module.identities.role_assignment_count
}

output "role_assignment_specs" {
  description = "Expected role assignment specs for testing."
  value       = module.identities.role_assignment_specs
}

output "cluster_id" {
  description = "Azure resource ID of the HCP cluster."
  value       = module.cluster.cluster_id
}

output "node_pool_id" {
  description = "Azure resource ID of the default node pool."
  value       = module.cluster.node_pool_id
}

output "managed_resource_group_name" {
  description = "Managed resource group name for the HCP cluster."
  value       = module.cluster.managed_resource_group_name
}

output "api_url" {
  description = "Kubernetes API URL when reported by the HCP API."
  value       = module.cluster.api_url
}

output "console_url" {
  description = "OpenShift console URL when reported by the HCP API."
  value       = module.cluster.console_url
}

output "dns_base_domain" {
  description = "Service-assigned HCP DNS zone (properties.dns.baseDomain)."
  value       = module.cluster.dns_base_domain
}

output "dns_base_domain_prefix" {
  description = "DNS label for the cluster (properties.dns.baseDomainPrefix)."
  value       = module.cluster.dns_base_domain_prefix
}

output "entra_client_id" {
  description = "Entra application (client) ID when enable_external_auth is true."
  value       = var.enable_external_auth ? module.entra[0].client_id : null
}

output "entra_issuer_url" {
  description = "OIDC issuer URL when enable_external_auth is true."
  value       = var.enable_external_auth ? module.entra[0].issuer_url : null
}

output "entra_client_secret_name" {
  description = "Key Vault secret name for the Entra confidential client secret. Value is never exported."
  value       = var.enable_external_auth ? module.entra[0].client_secret_key_vault_secret_name : null
}

output "entra_web_redirect_uris" {
  description = "Web redirect URIs Terraform registers on the Entra app."
  value       = var.enable_external_auth ? module.entra[0].web_redirect_uris : []
}

output "cluster_version" {
  value = var.cluster_version
}

output "cluster_channel" {
  value = var.cluster_channel
}

output "node_pool_name" {
  value = var.node_pool_name
}

output "node_pool_replicas" {
  value = var.node_pool_replicas
}

output "node_pool_vm_size" {
  value = var.node_pool_vm_size
}

output "node_pool_version" {
  value = var.node_pool_version
}

output "node_pool_channel" {
  value = var.node_pool_channel
}

output "api_visibility" {
  value = var.api_visibility
}

output "ingress_visibility" {
  value = var.ingress_visibility
}

output "jump_public_ip" {
  value = var.enable_jumpbox ? module.jumpbox[0].public_ip : null
}

output "jump_ssh_user" {
  value = var.enable_jumpbox ? module.jumpbox[0].ssh_user : null
}

output "jump_sshuttle_command" {
  value = var.enable_jumpbox ? module.jumpbox[0].sshuttle_command : null
}

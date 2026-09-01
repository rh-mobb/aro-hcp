output "identity_ids" {
  description = "User-assigned identity resource IDs keyed by operator name."
  value = {
    service                  = azurerm_user_assigned_identity.service.id
    cluster_api_azure        = azurerm_user_assigned_identity.cluster_api_azure.id
    control_plane            = azurerm_user_assigned_identity.control_plane.id
    cloud_controller_manager = azurerm_user_assigned_identity.cloud_controller_manager.id
    ingress                  = azurerm_user_assigned_identity.ingress.id
    disk_csi_driver          = azurerm_user_assigned_identity.disk_csi_driver.id
    file_csi_driver          = azurerm_user_assigned_identity.file_csi_driver.id
    image_registry           = azurerm_user_assigned_identity.image_registry.id
    cloud_network_config     = azurerm_user_assigned_identity.cloud_network_config.id
    kms                      = azurerm_user_assigned_identity.kms.id
    dp_disk_csi_driver       = azurerm_user_assigned_identity.dp_disk_csi_driver.id
    dp_file_csi_driver       = azurerm_user_assigned_identity.dp_file_csi_driver.id
    dp_image_registry        = azurerm_user_assigned_identity.dp_image_registry.id
  }
}

output "service_identity_id" {
  value = azurerm_user_assigned_identity.service.id
}

output "control_plane_operators" {
  value = local.control_plane_operators
}

output "data_plane_operators" {
  value = local.data_plane_operators
}

output "cluster_identity_ids" {
  value = local.cluster_identity_ids
}

output "role_assignment_count" {
  value = length(azurerm_role_assignment.this)
}

output "role_assignment_specs" {
  description = "Expected role assignment specs for testing."
  value       = local.assignment_specs
}

output "key_vault_id" {
  value = azurerm_key_vault.this.id
}

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "etcd_key_version" {
  value = azurerm_key_vault_key.etcd_encryption.version
}

output "etcd_encryption_key_name" {
  value = local.etcd_encryption_key_name
}

output "pull_secret_key_vault_secret_name" {
  value = var.pull_secret_key_vault_secret_name
}

output "key_vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "eso_identity_id" {
  description = "Resource ID of the ESO workload identity (not an HCP cluster identity)."
  value       = azurerm_user_assigned_identity.eso.id
}

output "eso_client_id" {
  description = "Client ID stamped onto the ESO ServiceAccount by the GitOps metadata Job."
  value       = azurerm_user_assigned_identity.eso.client_id
}

output "eso_federated_subject" {
  description = "OIDC subject Terraform trusts. GitOps must create this ServiceAccount name."
  value       = local.eso_federated_subject
}

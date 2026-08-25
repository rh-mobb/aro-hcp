output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "location" {
  value = azurerm_resource_group.this.location
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "subnet_id" {
  value = azurerm_subnet.worker.id
}

output "vnet_integration_subnet_id" {
  value = azapi_resource.vnet_integration_subnet.id
}

output "nsg_id" {
  value = azurerm_network_security_group.this.id
}

output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "key_vault_id" {
  value = azurerm_key_vault.this.id
}

output "etcd_key_version" {
  value = azurerm_key_vault_key.etcd_encryption.version
}

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

output "role_assignment_count" {
  value = length(azurerm_role_assignment.this)
}

output "role_assignment_specs" {
  description = "Expected role assignment specs for testing."
  value       = local.assignment_specs
}

resource "azurerm_user_assigned_identity" "service" {
  name                = local.identity_names.service
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "cluster_api_azure" {
  name                = local.identity_names.cluster_api_azure
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "control_plane" {
  name                = local.identity_names.control_plane
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "cloud_controller_manager" {
  name                = local.identity_names.cloud_controller_manager
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "ingress" {
  name                = local.identity_names.ingress
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "disk_csi_driver" {
  name                = local.identity_names.disk_csi_driver
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "file_csi_driver" {
  name                = local.identity_names.file_csi_driver
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "image_registry" {
  name                = local.identity_names.image_registry
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "cloud_network_config" {
  name                = local.identity_names.cloud_network_config
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "kms" {
  name                = local.identity_names.kms
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "dp_disk_csi_driver" {
  name                = local.identity_names.dp_disk_csi_driver
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "dp_file_csi_driver" {
  name                = local.identity_names.dp_file_csi_driver
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "dp_image_registry" {
  name                = local.identity_names.dp_image_registry
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

locals {
  identities = {
    service                  = azurerm_user_assigned_identity.service
    cluster_api_azure        = azurerm_user_assigned_identity.cluster_api_azure
    control_plane            = azurerm_user_assigned_identity.control_plane
    cloud_controller_manager = azurerm_user_assigned_identity.cloud_controller_manager
    ingress                  = azurerm_user_assigned_identity.ingress
    disk_csi_driver          = azurerm_user_assigned_identity.disk_csi_driver
    file_csi_driver          = azurerm_user_assigned_identity.file_csi_driver
    image_registry           = azurerm_user_assigned_identity.image_registry
    cloud_network_config     = azurerm_user_assigned_identity.cloud_network_config
    kms                      = azurerm_user_assigned_identity.kms
    dp_disk_csi_driver       = azurerm_user_assigned_identity.dp_disk_csi_driver
    dp_file_csi_driver       = azurerm_user_assigned_identity.dp_file_csi_driver
    dp_image_registry        = azurerm_user_assigned_identity.dp_image_registry
  }

  scopes = {
    vnet      = azurerm_virtual_network.this.id
    nsg       = azurerm_network_security_group.this.id
    subnet    = azurerm_subnet.worker.id
    key_vault = azurerm_key_vault.this.id
  }

  assignment_specs = [
    { key = "service-vnet", principal = "service", role = "service_managed_identity", scope = "vnet" },
    { key = "service-nsg", principal = "service", role = "service_managed_identity", scope = "nsg" },

    { key = "capi-vnet", principal = "cluster_api_azure", role = "cluster_api_provider", scope = "vnet" },
    { key = "service-reader-capi", principal = "service", role = "reader", scope_identity = "cluster_api_azure" },

    { key = "cp-vnet", principal = "control_plane", role = "control_plane_operator", scope = "vnet" },
    { key = "cp-nsg", principal = "control_plane", role = "control_plane_operator", scope = "nsg" },
    { key = "service-reader-cp", principal = "service", role = "reader", scope_identity = "control_plane" },

    { key = "ccm-vnet", principal = "cloud_controller_manager", role = "cloud_controller_manager", scope = "vnet" },
    { key = "ccm-nsg", principal = "cloud_controller_manager", role = "cloud_controller_manager", scope = "nsg" },
    { key = "service-reader-ccm", principal = "service", role = "reader", scope_identity = "cloud_controller_manager" },

    { key = "ingress-vnet", principal = "ingress", role = "ingress_operator", scope = "vnet" },
    { key = "service-reader-ingress", principal = "service", role = "reader", scope_identity = "ingress" },

    { key = "service-reader-disk-csi", principal = "service", role = "reader", scope_identity = "disk_csi_driver" },

    { key = "file-csi-vnet", principal = "file_csi_driver", role = "file_storage_operator", scope = "vnet" },
    { key = "file-csi-nsg", principal = "file_csi_driver", role = "file_storage_operator", scope = "nsg" },
    { key = "service-reader-file-csi", principal = "service", role = "reader", scope_identity = "file_csi_driver" },

    { key = "image-reg-vnet", principal = "image_registry", role = "image_registry_operator", scope = "vnet" },
    { key = "service-reader-image-reg", principal = "service", role = "reader", scope_identity = "image_registry" },

    { key = "cloud-net-subnet", principal = "cloud_network_config", role = "network_operator", scope = "subnet" },
    { key = "cloud-net-vnet", principal = "cloud_network_config", role = "network_operator", scope = "vnet" },
    { key = "service-reader-cloud-net", principal = "service", role = "reader", scope_identity = "cloud_network_config" },

    { key = "kms-kv", principal = "kms", role = "key_vault_crypto_user", scope = "key_vault" },
    { key = "service-reader-kms", principal = "service", role = "reader", scope_identity = "kms" },

    { key = "service-fed-dp-disk", principal = "service", role = "federated_credential", scope_identity = "dp_disk_csi_driver" },
    { key = "service-fed-dp-file", principal = "service", role = "federated_credential", scope_identity = "dp_file_csi_driver" },
    { key = "service-fed-dp-image", principal = "service", role = "federated_credential", scope_identity = "dp_image_registry" },

    { key = "dp-file-subnet", principal = "dp_file_csi_driver", role = "file_storage_operator", scope = "subnet" },
    { key = "dp-file-nsg", principal = "dp_file_csi_driver", role = "file_storage_operator", scope = "nsg" },
  ]

  assignment_specs_map = {
    for spec in local.assignment_specs : spec.key => spec
  }
}

resource "azurerm_role_assignment" "this" {
  for_each = local.assignment_specs_map

  scope                            = try(each.value.scope_identity, null) != null ? local.identities[each.value.scope_identity].id : local.scopes[each.value.scope]
  role_definition_id               = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids[each.value.role]}"
  principal_id                     = local.identities[each.value.principal].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

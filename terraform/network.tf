resource "azurerm_network_security_group" "this" {
  name                = var.nsg_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.address_prefix]
  tags                = local.tags
}

resource "azurerm_subnet" "worker" {
  name                              = var.subnet_name
  resource_group_name               = azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.subnet_prefix]
  private_endpoint_network_policies = "Disabled"
  default_outbound_access_enabled   = true
}

resource "azurerm_subnet_network_security_group_association" "worker" {
  subnet_id                 = azurerm_subnet.worker.id
  network_security_group_id = azurerm_network_security_group.this.id
}

# AzAPI: azurerm provider does not yet allow ARO HCP subnet delegation in validation.
resource "azapi_resource" "vnet_integration_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2023-05-01"
  name      = var.vnet_integration_subnet_name
  parent_id = azurerm_virtual_network.this.id

  body = {
    properties = {
      addressPrefix = var.vnet_integration_subnet_prefix
      delegations = [
        {
          name = "aro-hcp-delegation"
          properties = {
            serviceName = "Microsoft.RedHatOpenShift/hcpOpenShiftClusters"
          }
        }
      ]
    }
  }

  # Concurrent subnet writes on the same VNet return an Azure API conflict.
  depends_on = [
    azurerm_virtual_network.this,
    azurerm_subnet.worker,
    azurerm_network_security_group.this,
    azurerm_subnet_network_security_group_association.worker,
  ]
}

mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  cluster_name        = "test-cluster"
  resource_group_name = "test-rg"
  location            = "uksouth"
}

run "names_default_from_cluster_name" {
  command = plan

  variables {
    resource_group_name          = null
    vnet_name                    = null
    subnet_name                  = null
    vnet_integration_subnet_name = null
    nsg_name                     = null
  }

  assert {
    condition     = azurerm_resource_group.this.name == "test-cluster-rg"
    error_message = "resource_group_name must default to <cluster_name>-rg."
  }

  assert {
    condition     = azurerm_virtual_network.this.name == "test-cluster-vnet"
    error_message = "vnet_name must default to <cluster_name>-vnet."
  }

  assert {
    condition     = azurerm_subnet.worker.name == "test-cluster-worker"
    error_message = "subnet_name must default to <cluster_name>-worker."
  }

  assert {
    condition     = azapi_resource.vnet_integration_subnet.name == "test-cluster-integration"
    error_message = "vnet_integration_subnet_name must default to <cluster_name>-integration."
  }

  assert {
    condition     = azurerm_network_security_group.this.name == "test-cluster-nsg"
    error_message = "nsg_name must default to <cluster_name>-nsg."
  }
}

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      client_id       = "00000000-0000-0000-0000-000000000002"
      object_id       = "00000000-0000-0000-0000-000000000003"
      subscription_id = "00000000-0000-0000-0000-000000000004"
    }
  }
}
mock_provider "azapi" {}
mock_provider "random" {}

variables {
  cluster_name        = "test-cluster"
  resource_group_name = "test-rg"
  location            = "uksouth"
}

run "hcp_cluster_uses_preview_api" {
  command = plan

  assert {
    condition     = azapi_resource.hcp_cluster.type == "Microsoft.RedHatOpenShift/hcpOpenShiftClusters@2026-06-30-preview"
    error_message = "Cluster AzAPI type must be hcpOpenShiftClusters@2026-06-30-preview."
  }
}

run "hcp_cluster_disables_schema_validation" {
  command = plan

  assert {
    condition     = azapi_resource.hcp_cluster.schema_validation_enabled == false
    error_message = "Preview cluster AzAPI resource must set schema_validation_enabled = false."
  }
}

run "node_pool_is_cluster_child" {
  command = plan

  assert {
    condition     = azapi_resource.node_pool.type == "Microsoft.RedHatOpenShift/hcpOpenShiftClusters/nodePools@2026-06-30-preview"
    error_message = "Node pool AzAPI type must be hcpOpenShiftClusters/nodePools@2026-06-30-preview."
  }

  assert {
    condition     = azapi_resource.node_pool.schema_validation_enabled == false
    error_message = "Preview node pool AzAPI resource must set schema_validation_enabled = false."
  }

  assert {
    condition     = azapi_resource.node_pool.name == var.node_pool_name
    error_message = "Default node pool name must come from node_pool_name."
  }
}

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
mock_provider "azapi" {
  mock_data "azapi_resource_list" {
    defaults = {
      output = {
        enabled = [
          { name = "4.22.9", channelGroup = "stable" },
          { name = "4.22.10", channelGroup = "stable" },
        ]
      }
    }
  }
}

variables {
  cluster_name                = "test-cluster"
  resource_group_name         = "test-rg"
  resource_group_id           = "/subscriptions/sub/resourceGroups/test-rg"
  location                    = "uksouth"
  managed_resource_group_name = "test-cluster-managed"
  address_prefix              = "10.0.0.0/16"
  worker_subnet_id            = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/worker"
  vnet_integration_subnet_id  = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/integration"
  nsg_id                      = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/networkSecurityGroups/nsg"
  key_vault_name              = "cust-kv-test"
  etcd_key_version            = "abc123"
  etcd_encryption_key_name    = "etcd-data-kms-encryption-key"
  service_identity_id         = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/svc"
  control_plane_operators = {
    "cluster-api-azure" = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/capi"
  }
  data_plane_operators = {
    "disk-csi-driver" = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/dpdisk"
  }
  cluster_identity_ids = toset([
    "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/svc",
    "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/capi",
  ])
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

run "hcp_cluster_api_visibility_defaults_public" {
  command = plan

  assert {
    condition     = azapi_resource.hcp_cluster.body.properties.api.visibility == "Public"
    error_message = "Cluster API visibility must default to Public."
  }
}

run "hcp_cluster_api_visibility_private" {
  command = plan

  variables {
    api_visibility = "Private"
  }

  assert {
    condition     = azapi_resource.hcp_cluster.body.properties.api.visibility == "Private"
    error_message = "api_visibility=Private must set properties.api.visibility."
  }
}

run "hcp_cluster_ingress_visibility_defaults_public" {
  command = plan

  assert {
    condition     = azapi_resource.hcp_cluster.body.properties.ingress.type == "Public"
    error_message = "Cluster ingress visibility must default to Public."
  }
}

run "hcp_cluster_ingress_visibility_private" {
  command = plan

  variables {
    ingress_visibility = "Private"
  }

  assert {
    condition     = azapi_resource.hcp_cluster.body.properties.ingress.type == "Private"
    error_message = "ingress_visibility=Private must set properties.ingress.type."
  }
}

run "node_pool_version_must_be_enabled" {
  command = plan

  variables {
    node_pool_version = "9.9.9"
  }

  expect_failures = [
    azapi_resource.node_pool,
  ]
}

run "cluster_version_must_be_enabled_stream" {
  command = plan

  variables {
    cluster_version = "3.11"
  }

  expect_failures = [
    azapi_resource.hcp_cluster,
  ]
}

run "managed_resource_group_defaults_from_cluster_name" {
  command = plan

  variables {
    managed_resource_group_name = null
  }

  assert {
    condition     = azapi_resource.hcp_cluster.body.properties.platform.managedResourceGroup == "test-cluster-managed"
    error_message = "managed_resource_group_name must default to <cluster_name>-managed."
  }
}

# HCP cluster and default node pool via AzAPI (2026-06-30-preview).
# schema_validation_enabled = false: preview ARM schemas lag the API.
# Destroy of the last node pool is blocked (OCPBUGS-86702); scripts/destroy.sh
# removes azapi_resource.node_pool from state then runs terraform destroy.

resource "azapi_resource" "hcp_cluster" {
  type                      = "Microsoft.RedHatOpenShift/hcpOpenShiftClusters@${local.hcp_api_version}"
  parent_id                 = azurerm_resource_group.this.id
  name                      = var.cluster_name
  location                  = azurerm_resource_group.this.location
  schema_validation_enabled = false
  tags                      = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = tolist(local.cluster_identity_ids)
  }

  body = {
    properties = {
      version = {
        id           = var.cluster_version
        channelGroup = var.cluster_channel
      }
      dns = {}
      network = {
        networkType = "OVNKubernetes"
        podCidr     = var.pod_cidr
        serviceCidr = var.service_cidr
        machineCidr = var.address_prefix
        hostPrefix  = var.host_prefix
      }
      etcd = {
        dataEncryption = {
          keyManagementMode = "CustomerManaged"
          customerManaged = {
            encryptionType = "KMS"
            kms = {
              activeKey = {
                name    = local.etcd_encryption_key_name
                version = azurerm_key_vault_key.etcd_encryption.version
              }
              vaultName  = azurerm_key_vault.this.name
              visibility = var.vault_visibility
            }
          }
        }
      }
      api = {
        visibility = var.api_visibility
      }
      clusterImageRegistry = {
        state = var.cluster_image_registry_state
      }
      platform = {
        managedResourceGroup    = local.managed_resource_group_name
        subnetId                = azurerm_subnet.worker.id
        vnetIntegrationSubnetId = azapi_resource.vnet_integration_subnet.id
        outboundType            = var.outbound_type
        networkSecurityGroupId  = azurerm_network_security_group.this.id
        operatorsAuthentication = {
          userAssignedIdentities = {
            controlPlaneOperators  = local.control_plane_operators
            dataPlaneOperators     = local.data_plane_operators
            serviceManagedIdentity = azurerm_user_assigned_identity.service.id
          }
        }
      }
    }
  }

  response_export_values = ["properties"]

  timeouts {
    create = "120m"
    update = "120m"
    delete = "120m"
  }

  depends_on = [
    azurerm_role_assignment.this,
    azurerm_key_vault_key.etcd_encryption,
    azapi_resource.vnet_integration_subnet,
    azurerm_subnet_network_security_group_association.worker,
  ]
}

resource "azapi_resource" "node_pool" {
  type                      = "Microsoft.RedHatOpenShift/hcpOpenShiftClusters/nodePools@${local.hcp_api_version}"
  parent_id                 = azapi_resource.hcp_cluster.id
  name                      = var.node_pool_name
  location                  = azurerm_resource_group.this.location
  schema_validation_enabled = false
  tags                      = local.tags

  body = {
    properties = {
      version = {
        id           = var.node_pool_version
        channelGroup = var.node_pool_channel
      }
      platform = {
        subnetId = azurerm_subnet.worker.id
        vmSize   = var.node_pool_vm_size
        osDisk = {
          sizeGiB                = var.node_pool_disk_size_gib
          diskStorageAccountType = var.node_pool_disk_storage_account_type
        }
      }
      replicas = var.node_pool_replicas
    }
  }

  timeouts {
    create = "90m"
    update = "90m"
    delete = "90m"
  }
}

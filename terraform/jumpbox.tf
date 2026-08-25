resource "terraform_data" "jumpbox_prereqs" {
  count = var.enable_jumpbox ? 1 : 0

  lifecycle {
    precondition {
      condition     = can(cidrhost(var.jump_ssh_source_prefix, 0))
      error_message = "jump_ssh_source_prefix must be a CIDR (for example 1.2.3.4/32) when enable_jumpbox is true."
    }
    precondition {
      condition     = length(trimspace(var.jump_ssh_public_key)) > 0
      error_message = "jump_ssh_public_key is required when enable_jumpbox is true. Run: make jump-key"
    }
  }
}

module "jumpbox" {
  count  = var.enable_jumpbox ? 1 : 0
  source = "./modules/jumpbox"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
  cluster_name        = var.cluster_name
  vnet_name           = azurerm_virtual_network.this.name
  address_prefix      = var.address_prefix
  subnet_prefix       = var.jump_subnet_prefix
  ssh_source_prefix   = var.jump_ssh_source_prefix
  vm_size             = "Standard_D2s_v6"
  admin_username      = "fedora"
  ssh_public_key      = var.jump_ssh_public_key

  depends_on = [terraform_data.jumpbox_prereqs]
}

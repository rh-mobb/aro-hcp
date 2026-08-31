mock_provider "azurerm" {}

variables {
  resource_group_name = "test-rg"
  location            = "uksouth"
  cluster_name        = "test-cluster"
  vnet_name           = "test-vnet"
  address_prefix      = "10.0.0.0/16"
  subnet_prefix       = "10.0.2.0/28"
  ssh_source_prefix   = "203.0.113.10/32"
  ssh_public_key      = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB9ZPmSkVDQJ1HKpG4edUDTVSxf5OMQmRlk3uwkJ0zd/ test"
}

run "jump_subnet_is_28" {
  command = plan

  assert {
    condition     = azurerm_subnet.jump.address_prefixes[0] == "10.0.2.0/28"
    error_message = "Jump subnet must use the configured prefix."
  }
}

run "jump_vm_size" {
  command = plan

  assert {
    condition     = azurerm_linux_virtual_machine.jump.size == "Standard_D2s_v6"
    error_message = "Jump VM size must be Standard_D2s_v6."
  }
}

run "jump_nsg_allows_ssh_from_source" {
  command = plan

  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.jump.security_rule :
      r.source_address_prefix == "203.0.113.10/32" && r.destination_port_range == "22"
    ])
    error_message = "Jump NSG must allow SSH 22 from ssh_source_prefix."
  }
}

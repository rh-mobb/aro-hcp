output "public_ip" {
  value = azurerm_public_ip.jump.ip_address
}

output "ssh_user" {
  value = var.admin_username
}

output "sshuttle_command" {
  value = "sshuttle -r ${var.admin_username}@${azurerm_public_ip.jump.ip_address} --dns -e \"ssh -o StrictHostKeyChecking=accept-new -i config/jump\" ${var.address_prefix}"
}

output "subnet_address_prefix" {
  value = azurerm_subnet.jump.address_prefixes[0]
}

output "vm_size" {
  value = azurerm_linux_virtual_machine.jump.size
}

output "nsg_ssh_source_prefixes" {
  value = [
    for r in azurerm_network_security_group.jump.security_rule :
    r.source_address_prefix
    if r.destination_port_range == "22" && r.access == "Allow"
  ]
}

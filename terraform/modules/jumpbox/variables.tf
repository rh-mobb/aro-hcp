variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}
variable "cluster_name" { type = string }
variable "vnet_name" { type = string }
variable "address_prefix" { type = string }
variable "subnet_name" {
  type    = string
  default = "customer-jump-subnet"
}
variable "subnet_prefix" { type = string }
variable "nsg_name" {
  type    = string
  default = "customer-jump-nsg"
}
variable "ssh_source_prefix" { type = string }
variable "vm_size" {
  type    = string
  default = "Standard_D2s_v6"
}
variable "admin_username" {
  type    = string
  default = "fedora"
}
variable "ssh_public_key" { type = string }
variable "source_image_id" {
  type    = string
  default = "/communityGalleries/Fedora-5e266ba4-2250-406d-adad-5d73860d958f/images/Fedora-Cloud-44-x64/versions/latest"
}

# Reserved ANF CIDR is published for a sibling stack. This root does not create
# the delegated subnet. See issue #16 / AGENTS.md sibling section.
#
# cidrcontains() needs Terraform >= 1.11; CI is 1.9.8 — compare numeric IPv4 ranges.
locals {
  platform_cidrs = {
    vnet   = var.address_prefix
    worker = var.subnet_prefix
    integ  = var.vnet_integration_subnet_prefix
    jump   = var.jump_subnet_prefix
    netapp = var.netapp_subnet_prefix
  }

  platform_cidr_range = {
    for name, cidr in local.platform_cidrs : name => {
      start = (
        tonumber(split(".", cidrhost(cidr, 0))[0]) * 16777216 +
        tonumber(split(".", cidrhost(cidr, 0))[1]) * 65536 +
        tonumber(split(".", cidrhost(cidr, 0))[2]) * 256 +
        tonumber(split(".", cidrhost(cidr, 0))[3])
      )
      end = (
        tonumber(split(".", cidrhost(cidr, -1))[0]) * 16777216 +
        tonumber(split(".", cidrhost(cidr, -1))[1]) * 65536 +
        tonumber(split(".", cidrhost(cidr, -1))[2]) * 256 +
        tonumber(split(".", cidrhost(cidr, -1))[3])
      )
    }
  }
}

resource "terraform_data" "platform_cidrs" {
  lifecycle {
    precondition {
      condition = (
        local.platform_cidr_range.netapp.start >= local.platform_cidr_range.vnet.start &&
        local.platform_cidr_range.netapp.end <= local.platform_cidr_range.vnet.end
      )
      error_message = "netapp_subnet_prefix must be inside address_prefix (VNet CIDR)."
    }

    precondition {
      condition = !(
        local.platform_cidr_range.netapp.start <= local.platform_cidr_range.worker.end &&
        local.platform_cidr_range.worker.start <= local.platform_cidr_range.netapp.end
      )
      error_message = "netapp_subnet_prefix must not overlap the worker subnet (subnet_prefix)."
    }

    precondition {
      condition = !(
        local.platform_cidr_range.netapp.start <= local.platform_cidr_range.integ.end &&
        local.platform_cidr_range.integ.start <= local.platform_cidr_range.netapp.end
      )
      error_message = "netapp_subnet_prefix must not overlap the VNet integration subnet."
    }

    precondition {
      condition = !(
        local.platform_cidr_range.netapp.start <= local.platform_cidr_range.jump.end &&
        local.platform_cidr_range.jump.start <= local.platform_cidr_range.netapp.end
      )
      error_message = "netapp_subnet_prefix must not overlap jump_subnet_prefix (default 10.0.2.0/28)."
    }
  }
}

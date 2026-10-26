# A parent module with a submodule, as in every MLZ module with child resources: a virtual network locked
# through the module, and a subnet with its own interfaces call (a role assignment), passed up as
# lock_dependency. Azure applies the network's lock to the subnet's role assignments too.
terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}

variable "location" {
  type = string
}

variable "principal_id" {
  type = string
}

variable "resource_group_id" {
  type = string
}

variable "subnet_role_assignment" {
  type = bool
}

variable "suffix" {
  type = string
}

resource "azapi_resource" "virtual_network" {
  type      = "Microsoft.Network/virtualNetworks@2024-05-01"
  name      = "vnet-mlz-it-${var.suffix}"
  parent_id = var.resource_group_id
  location  = var.location
  body = {
    properties = {
      addressSpace = { addressPrefixes = ["10.42.0.0/24"] }
    }
  }
}

resource "azapi_resource" "subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = "snet-test"
  parent_id = azapi_resource.virtual_network.id
  body = {
    properties = {
      addressPrefixes = ["10.42.0.0/26"]
    }
  }
  locks = [azapi_resource.virtual_network.id]
}

module "subnet_interfaces" {
  source = "../../.."

  resource_id                      = azapi_resource.subnet.id
  location                         = var.location
  role_assignment_definition_scope = var.resource_group_id
  role_assignments = var.subnet_role_assignment ? {
    reader = { role_definition_id_or_name = "Reader", principal_id = var.principal_id }
  } : {}
}

module "interfaces" {
  source = "../../.."

  resource_id       = azapi_resource.virtual_network.id
  location          = var.location
  lock              = { kind = "CanNotDelete" }
  lock_dependencies = { subnet = module.subnet_interfaces.lock_dependency }
}

output "lock_resource_id" {
  value = module.interfaces.lock_resource_id
}

output "subnet_role_assignment_resource_ids" {
  value = module.subnet_interfaces.role_assignment_resource_ids
}

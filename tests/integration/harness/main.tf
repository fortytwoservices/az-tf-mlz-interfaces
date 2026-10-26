# A caller with its own child resources: a user-assigned identity with federated identity credentials,
# locked through the module, with the credentials passed as lock_dependencies.
terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}

variable "credential_names" {
  type = set(string)
}

variable "location" {
  type = string
}

variable "resource_group_id" {
  type = string
}

variable "suffix" {
  type = string
}

resource "azapi_resource" "identity" {
  type      = "Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30"
  name      = "id-mlz-it-${var.suffix}"
  parent_id = var.resource_group_id
  location  = var.location
}

resource "azapi_resource" "credential" {
  for_each = var.credential_names

  type      = "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30"
  name      = each.key
  parent_id = azapi_resource.identity.id
  body = {
    properties = {
      audiences = ["api://AzureADTokenExchange"]
      issuer    = "https://token.actions.githubusercontent.com"
      subject   = "repo:example-org/example-repo:environment:${each.key}"
    }
  }
  locks = [azapi_resource.identity.id]
}

module "interfaces" {
  source = "../../.."

  resource_id       = azapi_resource.identity.id
  location          = var.location
  lock              = { kind = "CanNotDelete" }
  lock_dependencies = { for name, credential in azapi_resource.credential : name => credential.id }
}

output "credential_names" {
  value = keys(azapi_resource.credential)
}

output "lock_resource_id" {
  value = module.interfaces.lock_resource_id
}

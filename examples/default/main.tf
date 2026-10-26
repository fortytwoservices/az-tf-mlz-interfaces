# Subscription from ARM_SUBSCRIPTION_ID or the Azure CLI; credentials from the Azure CLI or OIDC.
provider "azapi" {}

locals {
  location = "norwayeast"
  tags     = { example = "default" }
}

data "azapi_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azapi_resource" "resource_group" {
  type      = "Microsoft.Resources/resourceGroups@2024-11-01"
  name      = "rg-mlz-ifc-${random_string.suffix.result}"
  parent_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  location  = local.location

  response_export_values = []
  tags                   = local.tags
}

resource "azapi_resource" "log_analytics_workspace" {
  type      = "Microsoft.OperationalInsights/workspaces@2023-09-01"
  name      = "log-mlz-ifc-${random_string.suffix.result}"
  parent_id = azapi_resource.resource_group.id
  location  = local.location
  body = {
    properties = {
      retentionInDays = 30
      sku             = { name = "PerGB2018" }
    }
  }

  response_export_values = []
  tags                   = local.tags
}

# The resource the interfaces are created on; in an MLZ module this is azapi_resource.this.
resource "azapi_resource" "public_ip_address" {
  type      = "Microsoft.Network/publicIPAddresses@2025-07-01"
  name      = "pip-mlz-ifc-${random_string.suffix.result}"
  parent_id = azapi_resource.resource_group.id
  location  = local.location
  body = {
    sku        = { name = "Standard", tier = "Regional" }
    properties = { publicIPAllocationMethod = "Static" }
  }

  response_export_values = []
  tags                   = local.tags
}

module "interfaces" {
  source = "../../"

  resource_id                      = azapi_resource.public_ip_address.id
  location                         = local.location
  role_assignment_definition_scope = azapi_resource.resource_group.id
  diagnostic_settings = {
    workspace = {
      workspace_resource_id = azapi_resource.log_analytics_workspace.id
      logs                  = [{ category_group = "allLogs" }]
      metrics               = [{ category = "AllMetrics" }]
    }
  }
  lock = {
    kind = "CanNotDelete"
  }
  role_assignments = {
    deployer_reader = {
      role_definition_id_or_name = "Reader"
      principal_id               = data.azapi_client_config.current.object_id
    }
  }
}

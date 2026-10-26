mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/publicIPAddresses/pip-test/providers/Microsoft.Authorization/locks/lock-test"
    }
  }
  mock_data "azapi_resource_list" {
    defaults = {
      output = {
        results = [
          {
            id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
            role_name = "Reader"
          }
        ]
      }
    }
  }
}
mock_provider "random" {}
mock_provider "time" {}

variables {
  location                         = "norwayeast"
  resource_id                      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/publicIPAddresses/pip-test"
  role_assignment_definition_scope = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
}

run "nothing_by_default" {
  command = apply

  assert {
    condition     = length(azapi_resource.lock) + length(time_sleep.lock_removal) + length(azapi_resource.role_assignments) + length(azapi_resource.diagnostic_settings) == 0
    error_message = "Nothing should be created without inputs."
  }
  assert {
    condition     = output.lock_resource_id == null && length(output.role_assignment_resource_ids) == 0 && length(output.diagnostic_setting_resource_ids) == 0
    error_message = "The outputs should be empty without inputs."
  }
  assert {
    condition     = length(output.lock_dependency) == 64
    error_message = "lock_dependency should be a SHA-256 hash."
  }
}

run "lock" {
  command = apply

  variables {
    lock = { kind = "CanNotDelete" }
    lock_dependencies = {
      credential = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-test/federatedIdentityCredentials/github"
    }
  }

  assert {
    condition     = azapi_resource.lock[0].name == "lock-CanNotDelete" && azapi_resource.lock[0].type == "Microsoft.Authorization/locks@2020-05-01" && azapi_resource.lock[0].parent_id == var.resource_id
    error_message = "The lock should be named after its kind and placed on the resource with the default type."
  }
  assert {
    condition     = azapi_resource.lock[0].body.properties.level == "CanNotDelete" && output.lock_resource_id == azapi_resource.lock[0].id
    error_message = "The lock should have the requested level and be output."
  }
  assert {
    condition     = time_sleep.lock_removal[0].destroy_duration == "30s" && time_sleep.lock_removal[0].triggers.resource_id == var.resource_id
    error_message = "A lock should come with the 30s removal pause, replaced with the resource."
  }
  assert {
    condition     = time_sleep.lock_removal[0].triggers.children == sha256(jsonencode([var.diagnostic_settings, var.role_assignments, []])) && time_sleep.lock_removal[0].triggers.lock_dependencies == sha256(jsonencode(var.lock_dependencies))
    error_message = "Changes to the role assignments, diagnostic settings or lock_dependencies should replace the pause, and with it the lock."
  }
  assert {
    condition     = output.lock_dependency != run.nothing_by_default.lock_dependency
    error_message = "lock_dependency should change with lock_dependencies, so a parent's lock follows grandchildren too."
  }
}

run "lock_named" {
  command = apply

  variables {
    lock = { kind = "ReadOnly", name = "lock-custom", notes = "Managed by Terraform." }
  }

  assert {
    condition     = azapi_resource.lock[0].name == "lock-custom" && azapi_resource.lock[0].body.properties.notes == "Managed by Terraform."
    error_message = "The lock should use the given name and notes."
  }
}

run "role_assignments" {
  command = apply

  variables {
    role_assignments = {
      by_name = {
        role_definition_id_or_name = "Reader"
        principal_id               = "55555555-5555-5555-5555-555555555555"
      }
      tenant_level_id = {
        role_definition_id_or_name       = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
        principal_id                     = "66666666-6666-6666-6666-666666666666"
        skip_service_principal_aad_check = true
        description                      = "Read the resource."
      }
      management_group_role = {
        role_definition_id_or_name = "/providers/Microsoft.Management/managementGroups/mg-test/providers/Microsoft.Authorization/roleDefinitions/99999999-9999-9999-9999-999999999999"
        principal_id               = "55555555-5555-5555-5555-555555555555"
        condition                  = "@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals 'logs'"
        condition_version          = "2.0"
      }
      named = {
        name                                   = "77777777-7777-7777-7777-777777777777"
        role_definition_id_or_name             = "Reader"
        principal_id                           = "88888888-8888-8888-8888-888888888888"
        delegated_managed_identity_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-delegated"
      }
    }
  }

  assert {
    condition     = azapi_resource.role_assignments["by_name"].body.properties.roleDefinitionId == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
    error_message = "A role name should resolve to the role definition ID found in the lookup scope."
  }
  assert {
    condition     = azapi_resource.role_assignments["tenant_level_id"].body.properties.roleDefinitionId == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
    error_message = "A tenant-level role definition ID should be qualified with the resource's subscription."
  }
  assert {
    condition     = azapi_resource.role_assignments["management_group_role"].body.properties.roleDefinitionId == "/providers/Microsoft.Management/managementGroups/mg-test/providers/Microsoft.Authorization/roleDefinitions/99999999-9999-9999-9999-999999999999"
    error_message = "A management-group-scoped role definition ID should be passed through unchanged."
  }
  assert {
    condition     = azapi_resource.role_assignments["tenant_level_id"].body.properties.principalType == "ServicePrincipal" && azapi_resource.role_assignments["by_name"].body.properties.principalType == null
    error_message = "skip_service_principal_aad_check should set principalType to ServicePrincipal, and only then."
  }
  assert {
    condition     = azapi_resource.role_assignments["named"].name == "77777777-7777-7777-7777-777777777777"
    error_message = "An explicit name should be used."
  }
  assert {
    condition = alltrue([for key, values in {
      named                 = { name = "77777777-7777-7777-7777-777777777777", delegated_managed_identity_resource_id = var.role_assignments["named"].delegated_managed_identity_resource_id }
      tenant_level_id       = { description = "Read the resource." }
      management_group_role = { condition = var.role_assignments["management_group_role"].condition, condition_version = "2.0" }
      } : alltrue([for field, value in values : azapi_resource.role_assignments[key].replace_triggers_external_values[field] == value])
    ])
    error_message = "Name, delegated identity, description, condition and condition version should be replacement inputs."
  }
  assert {
    condition     = azapi_resource.role_assignments["by_name"].replace_triggers_external_values.principal_id == "55555555-5555-5555-5555-555555555555" && azapi_resource.role_assignments["by_name"].replace_triggers_external_values.role_definition_id_or_name == "reader"
    error_message = "Principal and role should be replacement inputs, compared case-insensitively."
  }
  assert {
    condition     = alltrue([for assignment in azapi_resource.role_assignments : assignment.parent_id == var.resource_id && assignment.type == "Microsoft.Authorization/roleAssignments@2022-04-01"]) && keys(output.role_assignment_resource_ids) == ["by_name", "management_group_role", "named", "tenant_level_id"]
    error_message = "Role assignments should be created on the resource with the default type, and output by key."
  }
  assert {
    condition     = output.lock_dependency != run.nothing_by_default.lock_dependency
    error_message = "lock_dependency should change with the role assignments."
  }
}

run "role_assignments_outside_a_subscription" {
  command = apply

  variables {
    resource_id                      = "/providers/Microsoft.Management/managementGroups/mg-test"
    role_assignment_definition_scope = "/providers/Microsoft.Management/managementGroups/mg-test"
    role_assignments = {
      tenant_level_id = {
        role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
        principal_id               = "55555555-5555-5555-5555-555555555555"
      }
    }
  }

  assert {
    condition     = azapi_resource.role_assignments["tenant_level_id"].body.properties.roleDefinitionId == "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
    error_message = "Without a subscription in resource_id, a tenant-level role definition ID should be left as it is."
  }
}

run "resource_id_in_other_casing" {
  command = apply

  variables {
    resource_id = "/Subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/publicIPAddresses/pip-test"
    role_assignments = {
      tenant_level_id = {
        role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
        principal_id               = "55555555-5555-5555-5555-555555555555"
      }
    }
  }

  assert {
    condition     = azapi_resource.role_assignments["tenant_level_id"].body.properties.roleDefinitionId == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
    error_message = "Resource IDs are case-insensitive: /Subscriptions/ should be accepted and its subscription used."
  }
}

run "unknown_role_name" {
  command = plan

  variables {
    role_assignments = {
      reader = {
        role_definition_id_or_name = "Readr"
        principal_id               = "55555555-5555-5555-5555-555555555555"
      }
    }
  }

  expect_failures = [azapi_resource.role_assignments]
}

run "diagnostic_settings" {
  command = apply

  variables {
    diagnostic_settings = {
      workspace = {
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test"
        logs                  = [{ category_group = "allLogs" }]
        metrics               = [{ category = "AllMetrics" }]
      }
      named = {
        name                  = "diag-custom"
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test"
        logs                  = [{ category = "DDoSProtectionNotifications" }]
      }
    }
  }

  assert {
    condition     = azapi_resource.diagnostic_settings["workspace"].name == "diag-workspace" && azapi_resource.diagnostic_settings["named"].name == "diag-custom"
    error_message = "Diagnostic settings should be named diag-<key> unless a name is given."
  }
  assert {
    condition     = azapi_resource.diagnostic_settings["workspace"].parent_id == var.resource_id && azapi_resource.diagnostic_settings["workspace"].type == "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
    error_message = "Diagnostic settings should be created on the resource with the default type."
  }
  assert {
    condition     = azapi_resource.diagnostic_settings["workspace"].body.properties.workspaceId == var.diagnostic_settings["workspace"].workspace_resource_id && azapi_resource.diagnostic_settings["workspace"].body.properties.logs[0].categoryGroup == "allLogs" && azapi_resource.diagnostic_settings["workspace"].body.properties.metrics[0].category == "AllMetrics"
    error_message = "The diagnostic setting should send the requested logs and metrics to the workspace."
  }
  assert {
    condition     = azapi_resource.diagnostic_settings["workspace"].list_unique_id_property["properties.logs"] == "category,categoryGroup" && contains(azapi_resource.diagnostic_settings["workspace"].ignore_other_items_in_list, "properties.logs")
    error_message = "Log entries should be matched by category, with Azure's extra disabled entries ignored."
  }
  assert {
    condition     = azapi_resource.diagnostic_settings["workspace"].replace_triggers_external_values.workspace_resource_id == var.diagnostic_settings["workspace"].workspace_resource_id
    error_message = "Any change to a diagnostic setting's inputs should recreate it."
  }
  assert {
    condition     = keys(output.diagnostic_setting_resource_ids) == ["named", "workspace"]
    error_message = "Diagnostic setting IDs should be output by key."
  }
  assert {
    condition     = output.lock_dependency != run.nothing_by_default.lock_dependency
    error_message = "lock_dependency should change with the diagnostic settings."
  }
}

run "diagnostic_settings_ignored_paths" {
  command = apply

  variables {
    diagnostic_settings = {
      workspace = {
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test"
        logs                  = [{ category_group = "allLogs" }]
      }
    }
    ignore_body_changes = {
      insights_diagnostic_settings = ["properties.logs", "properties.workspaceId.unused"]
    }
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = !contains(keys(azapi_resource.diagnostic_settings["workspace"].replace_triggers_external_values), "logs") && !contains(keys(azapi_resource.diagnostic_settings["workspace"].replace_triggers_external_values), "workspace_resource_id")
    error_message = "Inputs at an ignored body path, or under or above one, should not recreate the setting."
  }
  assert {
    condition     = contains(keys(azapi_resource.diagnostic_settings["workspace"].replace_triggers_external_values), "metrics") && contains(keys(azapi_resource.diagnostic_settings["workspace"].replace_triggers_external_values), "name")
    error_message = "The other inputs should still recreate the setting."
  }
  assert {
    condition     = time_sleep.lock_removal[0].triggers.children == sha256(jsonencode([var.diagnostic_settings, var.role_assignments, ["logs", "workspace_resource_id"]]))
    error_message = "Ignoring inputs changes the setting's replacement trigger, so it should cycle the lock too."
  }
}

run "azapi_settings_reach_every_resource" {
  command = apply

  # ignore_body_changes is write-only, so a test cannot read it back; setting it proves the slots are
  # accepted. Which resource reads which slot is left to review.
  variables {
    lock = { kind = "CanNotDelete" }
    role_assignments = {
      reader = {
        role_definition_id_or_name = "Reader"
        principal_id               = "55555555-5555-5555-5555-555555555555"
      }
    }
    diagnostic_settings = {
      workspace = {
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test"
        metrics               = [{ category = "AllMetrics" }]
      }
    }
    resource_types = {
      authorization_locks            = "Microsoft.Authorization/locks@2016-09-01"
      authorization_role_assignments = "Microsoft.Authorization/roleAssignments@2020-04-01-preview"
      # No other diagnostic settings API version has this body's shape (2020-01-01-preview has no
      # metrics), so the insights_diagnostic_settings slot is not overridden here.
    }
    ignore_body_changes = {
      authorization_locks            = ["properties.notes"]
      authorization_role_assignments = ["properties.description"]
      insights_diagnostic_settings   = ["properties.logs"]
    }
    retry    = { error_message_regex = ["AnotherOperationInProgress"] }
    timeouts = { create = "15m" }
  }

  assert {
    condition     = azapi_resource.lock[0].type == "Microsoft.Authorization/locks@2016-09-01" && azapi_resource.role_assignments["reader"].type == "Microsoft.Authorization/roleAssignments@2020-04-01-preview"
    error_message = "resource_types overrides should reach the lock and the role assignments."
  }
  assert {
    condition     = alltrue([for r in [azapi_resource.lock[0], azapi_resource.role_assignments["reader"], azapi_resource.diagnostic_settings["workspace"]] : r.retry.error_message_regex == tolist(["AnotherOperationInProgress"]) && r.timeouts.create == "15m"])
    error_message = "retry and timeouts should reach every resource."
  }
}

run "invalid_resource_id" {
  command = plan

  variables {
    resource_id = "pip-test"
  }

  expect_failures = [var.resource_id]
}

run "invalid_lock_kind" {
  command = plan

  variables {
    lock = { kind = "Delete" }
  }

  expect_failures = [var.lock]
}

run "invalid_delegated_identity" {
  command = plan

  variables {
    role_assignments = {
      reader = {
        role_definition_id_or_name             = "Reader"
        principal_id                           = "55555555-5555-5555-5555-555555555555"
        delegated_managed_identity_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

run "diagnostic_setting_without_destination" {
  command = plan

  variables {
    diagnostic_settings = {
      nowhere = {
        metrics = [{ category = "AllMetrics" }]
      }
    }
  }

  expect_failures = [var.diagnostic_settings]
}

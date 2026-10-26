mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-test"
      output = {
        properties = {
          clientId    = "22222222-2222-2222-2222-222222222222"
          principalId = "33333333-3333-3333-3333-333333333333"
          tenantId    = "44444444-4444-4444-4444-444444444444"
        }
      }
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
  location  = "norwayeast"
  name      = "id-test"
  parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
}

run "defaults" {
  command = apply

  assert {
    condition     = azapi_resource.this.type == "Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30"
    error_message = "The identity should use the default resource type."
  }
  assert {
    condition     = azapi_resource.this.name == var.name && azapi_resource.this.parent_id == var.parent_id && azapi_resource.this.location == var.location
    error_message = "The identity should be created with name, parent_id and location."
  }
  assert {
    condition     = azapi_resource.this.body.properties.isolationScope == "None"
    error_message = "isolationScope should be sent with Azure's default, so that changing it back reaches Azure."
  }
  assert {
    condition     = azapi_resource.this.retry == null
    error_message = "retry should be unset by default."
  }
  assert {
    condition     = azapi_resource.this.timeouts == null
    error_message = "timeouts should be unset by default."
  }
  assert {
    condition     = length(coalesce(azapi_resource.this.tags, {})) == 0 # computed: the mock returns {}
    error_message = "tags should be unset by default."
  }
  assert {
    condition     = length(azapi_resource.lock) + length(time_sleep.lock_removal) + length(azapi_resource.role_assignments) + length(module.federated_identity_credential) == 0
    error_message = "No lock, role assignment or credential should be created by default."
  }
  assert {
    condition     = output.resource_id == azapi_resource.this.id && output.name == var.name
    error_message = "resource_id and name should come from the identity."
  }
  assert {
    condition     = output.principal_id == "33333333-3333-3333-3333-333333333333" && output.client_id == "22222222-2222-2222-2222-222222222222" && output.tenant_id == "44444444-4444-4444-4444-444444444444"
    error_message = "principal_id, client_id and tenant_id should come from the identity's exported properties."
  }
  assert {
    condition     = length(output.federated_identity_credential_resource_ids) == 0
    error_message = "No credential IDs should be output by default."
  }
}

run "identity_options" {
  command = apply

  variables {
    isolation_scope = "Regional"
    tags            = { environment = "test" }
  }

  assert {
    condition     = azapi_resource.this.body.properties.isolationScope == "Regional"
    error_message = "isolation_scope should map to properties.isolationScope."
  }
  assert {
    condition     = azapi_resource.this.tags == tomap({ environment = "test" })
    error_message = "tags should be set on the identity."
  }
}

run "federated_identity_credentials" {
  command = apply

  variables {
    federated_identity_credentials = {
      github-main = {
        issuer  = "https://token.actions.githubusercontent.com"
        subject = "repo:example/example:ref:refs/heads/main"
      }
      github-pr = {
        issuer    = "https://token.actions.githubusercontent.com"
        subject   = "repo:example/example:pull_request"
        audiences = ["api://custom"]
      }
    }
  }

  assert {
    condition     = toset(keys(module.federated_identity_credential)) == toset(["github-main", "github-pr"])
    error_message = "One credential module should be created per map entry."
  }
  assert {
    condition     = module.federated_identity_credential["github-main"].name == "github-main"
    error_message = "The map key should be the credential name."
  }
  assert {
    condition     = keys(output.federated_identity_credential_resource_ids) == ["github-main", "github-pr"]
    error_message = "Credential resource IDs should be output by credential name."
  }
}

run "lock_defaults" {
  command = apply

  variables {
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = azapi_resource.lock[0].name == "lock-CanNotDelete" && azapi_resource.lock[0].type == "Microsoft.Authorization/locks@2020-05-01"
    error_message = "The lock should get a name from its kind and the default resource type."
  }
  assert {
    condition     = azapi_resource.lock[0].parent_id == azapi_resource.this.id && azapi_resource.lock[0].body.properties.level == "CanNotDelete"
    error_message = "The lock should be placed on the identity with the requested level."
  }
  assert {
    condition     = time_sleep.lock_removal[0].destroy_duration == "30s"
    error_message = "A lock should come with the 30s removal pause."
  }
  assert {
    condition     = time_sleep.lock_removal[0].triggers.identity_id == azapi_resource.this.id
    error_message = "The pause should be replaced with the identity, so it also runs when a locked identity is replaced."
  }
  assert {
    condition     = time_sleep.lock_removal[0].triggers.children == sha256(jsonencode([var.federated_identity_credentials, var.role_assignments]))
    error_message = "A change to the credentials or role assignments should replace the pause, and with it the lock."
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
      }
      management_group_role = {
        role_definition_id_or_name = "/providers/Microsoft.Management/managementGroups/mg-test/providers/Microsoft.Authorization/roleDefinitions/99999999-9999-9999-9999-999999999999"
        principal_id               = "55555555-5555-5555-5555-555555555555"
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
    error_message = "A role name should resolve to the role definition ID found in the resource group."
  }
  assert {
    condition     = azapi_resource.role_assignments["tenant_level_id"].body.properties.roleDefinitionId == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
    error_message = "A tenant-level role definition ID should be qualified with the subscription."
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
    condition     = azapi_resource.role_assignments["named"].name == "77777777-7777-7777-7777-777777777777" && azapi_resource.role_assignments["named"].replace_triggers_external_values.name == "77777777-7777-7777-7777-777777777777"
    error_message = "An explicit name should be used and should replace the assignment when it changes."
  }
  assert {
    condition     = azapi_resource.role_assignments["named"].replace_triggers_external_values.delegated_managed_identity_resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-delegated"
    error_message = "A changed delegated identity should replace the assignment."
  }
  assert {
    condition     = azapi_resource.role_assignments["by_name"].replace_triggers_external_values.name == null
    error_message = "A generated name should not be a replacement trigger."
  }
  assert {
    condition     = alltrue([for ra in azapi_resource.role_assignments : ra.parent_id == azapi_resource.this.id && ra.type == "Microsoft.Authorization/roleAssignments@2022-04-01"])
    error_message = "Role assignments should be created on the identity with the default resource type."
  }
}

run "azapi_settings_reach_every_resource" {
  command = apply

  # ignore_body_changes is write-only, so a test cannot read it back, and avm_interface_ignore_body_changes
  # only checks that the argument uses the variable, not which slot. Setting it here proves the slots are
  # accepted; which resource reads which slot is left to review.
  variables {
    lock = { kind = "CanNotDelete" }
    role_assignments = {
      reader = {
        role_definition_id_or_name = "Reader"
        principal_id               = "55555555-5555-5555-5555-555555555555"
      }
    }
    resource_types = {
      managedidentity_user_assigned_identities = "Microsoft.ManagedIdentity/userAssignedIdentities@2025-05-31-preview"
      authorization_locks                      = "Microsoft.Authorization/locks@2016-09-01"
      authorization_role_assignments           = "Microsoft.Authorization/roleAssignments@2020-04-01-preview"
    }
    ignore_body_changes = {
      managedidentity_user_assigned_identities = ["properties.isolationScope"]
      authorization_locks                      = ["properties.notes"]
      authorization_role_assignments           = ["properties.description"]
    }
    retry = {
      error_message_regex = ["AnotherOperationInProgress"]
    }
    timeouts = {
      create = "15m"
    }
  }

  assert {
    condition     = azapi_resource.this.type == "Microsoft.ManagedIdentity/userAssignedIdentities@2025-05-31-preview" && azapi_resource.lock[0].type == "Microsoft.Authorization/locks@2016-09-01" && azapi_resource.role_assignments["reader"].type == "Microsoft.Authorization/roleAssignments@2020-04-01-preview"
    error_message = "resource_types overrides should reach the identity, the lock and the role assignments."
  }
  assert {
    condition     = alltrue([for r in [azapi_resource.this, azapi_resource.lock[0], azapi_resource.role_assignments["reader"]] : r.retry.error_message_regex == tolist(["AnotherOperationInProgress"]) && r.timeouts.create == "15m"])
    error_message = "retry and timeouts should reach every resource in the root module."
  }
}

run "invalid_name" {
  command = plan

  variables {
    name = "-bad"
  }

  expect_failures = [var.name]
}

run "invalid_parent_id" {
  command = plan

  variables {
    parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000"
  }

  expect_failures = [var.parent_id]
}

run "invalid_isolation_scope" {
  command = plan

  variables {
    isolation_scope = "Global"
  }

  expect_failures = [var.isolation_scope]
}

run "empty_isolation_scope" {
  command = plan

  variables {
    isolation_scope = ""
  }

  expect_failures = [var.isolation_scope]
}

run "null_isolation_scope" {
  command = plan

  variables {
    isolation_scope = null
  }

  assert {
    condition     = azapi_resource.this.body.properties.isolationScope == "None"
    error_message = "A null isolation_scope should fall back to the default."
  }
}

run "invalid_lock_kind" {
  command = plan

  variables {
    lock = { kind = "Delete" }
  }

  expect_failures = [var.lock]
}

run "too_many_credentials" {
  command = plan

  variables {
    federated_identity_credentials = {
      for i in range(21) : "credential-${i}" => {
        issuer  = "https://token.actions.githubusercontent.com"
        subject = "repo:example/example:environment:env-${i}"
      }
    }
  }

  expect_failures = [var.federated_identity_credentials]
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

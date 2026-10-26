# Real Azure, no mocks: ARM_SUBSCRIPTION_ID=<test subscription> scripts/integration.sh
# Proves what mocks cannot: the interfaces are accepted by Azure on a public IP; role assignments and
# diagnostic settings can be removed, changed and force-replaced while the lock stays configured; a
# caller's own child resource can be deleted under the lock through lock_dependencies; and everything is
# destroyed cleanly (the lock first).

run "setup" {
  module {
    source = "./tests/integration/setup"
  }
}

run "create" {
  variables {
    resource_id                      = run.setup.public_ip_address_id
    location                         = run.setup.location
    role_assignment_definition_scope = run.setup.resource_group_id
    diagnostic_settings = {
      workspace = {
        workspace_resource_id = run.setup.workspace_id
        logs                  = [{ category_group = "allLogs" }]
        metrics               = [{ category = "AllMetrics" }]
      }
    }
    lock = { kind = "CanNotDelete" }
    role_assignments = {
      reader = { role_definition_id_or_name = "Reader", principal_id = run.setup.object_id }
    }
  }

  assert {
    condition     = output.lock_resource_id != null && length(output.role_assignment_resource_ids) == 1 && length(output.diagnostic_setting_resource_ids) == 1
    error_message = "The lock, the role assignment and the diagnostic setting should be created."
  }
}

run "replace_child_under_lock" {
  # The documented way to force-replace a child of a locked resource: replace the pause in the same run.
  variables {
    resource_id                      = run.setup.public_ip_address_id
    location                         = run.setup.location
    role_assignment_definition_scope = run.setup.resource_group_id
    diagnostic_settings = {
      workspace = {
        workspace_resource_id = run.setup.workspace_id
        logs                  = [{ category_group = "allLogs" }]
        metrics               = [{ category = "AllMetrics" }]
      }
    }
    lock = { kind = "CanNotDelete" }
    role_assignments = {
      reader = { role_definition_id_or_name = "Reader", principal_id = run.setup.object_id }
    }
  }

  plan_options {
    replace = [azapi_resource.diagnostic_settings["workspace"], time_sleep.lock_removal[0]]
  }

  assert {
    condition     = length(output.diagnostic_setting_resource_ids) == 1 && output.lock_resource_id != null
    error_message = "The diagnostic setting should be recreated and the lock back."
  }
}

run "change_and_remove_children_under_lock" {
  # The diagnostic setting changes to one category (recreated) and the role assignment is deleted, with
  # the lock still configured.
  variables {
    resource_id                      = run.setup.public_ip_address_id
    location                         = run.setup.location
    role_assignment_definition_scope = run.setup.resource_group_id
    diagnostic_settings = {
      workspace = {
        workspace_resource_id = run.setup.workspace_id
        logs                  = [{ category = "DDoSProtectionNotifications" }]
      }
    }
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = length(output.role_assignment_resource_ids) == 0 && length(output.diagnostic_setting_resource_ids) == 1 && output.lock_resource_id != null
    error_message = "The role assignment should be gone, the diagnostic setting changed and the lock back."
  }
}

run "ignore_a_diagnostic_path_under_lock" {
  # Ignoring a path changes the diagnostic setting's replacement trigger, so the setting is recreated, and
  # the lock has to be removed around it.
  variables {
    resource_id                      = run.setup.public_ip_address_id
    location                         = run.setup.location
    role_assignment_definition_scope = run.setup.resource_group_id
    diagnostic_settings = {
      workspace = {
        workspace_resource_id = run.setup.workspace_id
        logs                  = [{ category = "DDoSProtectionNotifications" }]
      }
    }
    lock                = { kind = "CanNotDelete" }
    ignore_body_changes = { insights_diagnostic_settings = ["properties.logs"] }
  }

  assert {
    condition     = length(output.diagnostic_setting_resource_ids) == 1 && output.lock_resource_id != null
    error_message = "The diagnostic setting should be recreated under the lock, and the lock back."
  }
}

run "caller_with_three_credentials" {
  module {
    source = "./tests/integration/harness"
  }

  variables {
    credential_names  = ["one", "three", "two"]
    location          = run.setup.location
    resource_group_id = run.setup.resource_group_id
    suffix            = run.setup.suffix
  }

  assert {
    condition     = length(output.credential_names) == 3 && output.lock_resource_id != null
    error_message = "The identity should be locked with three credentials."
  }
}

run "caller_removes_a_credential_under_lock" {
  module {
    source = "./tests/integration/harness"
  }

  variables {
    credential_names  = ["one", "two"]
    location          = run.setup.location
    resource_group_id = run.setup.resource_group_id
    suffix            = run.setup.suffix
  }

  assert {
    condition     = output.credential_names == ["one", "two"] && output.lock_resource_id != null
    error_message = "The credential should be deleted under the lock, and the lock back."
  }
}

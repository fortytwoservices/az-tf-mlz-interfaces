module "avm_interfaces" {
  source  = "Azure/avm-utl-interfaces/azure"
  version = "0.9.0"

  enable_telemetry                 = false # defaults to true
  location                         = var.location
  diagnostic_settings_v2           = var.diagnostic_settings
  lock                             = var.lock
  role_assignments                 = local.role_assignments
  role_assignment_definition_scope = coalesce(var.role_assignment_definition_scope, var.resource_id)
}

resource "azapi_resource" "diagnostic_settings" {
  for_each = module.avm_interfaces.diagnostic_settings_azapi_v2

  type                 = var.resource_types.insights_diagnostic_settings
  name                 = coalesce(each.value.name, "diag-${each.key}")
  parent_id            = var.resource_id
  body                 = each.value.body
  ignore_body_changes  = length(var.ignore_body_changes.insights_diagnostic_settings) > 0 ? var.ignore_body_changes.insights_diagnostic_settings : null
  ignore_null_property = true
  # Azure also returns the type's log categories (or category groups) that were not requested, disabled,
  # which azapi would plan to remove on every run. Match entries by category instead of by position and
  # ignore the extra ones (seen on public IPs: allLogs requested, audit returned disabled).
  ignore_other_items_in_list = ["properties.logs", "properties.metrics"]
  list_unique_id_property = {
    "properties.logs"    = "category,categoryGroup"
    "properties.metrics" = "category"
  }
  # A removed destination (a null that ignore_null_property drops) or a removed log category (an ignored
  # extra item) would not reach Azure, so any change recreates the setting, except at ignored body paths.
  replace_triggers_external_values = {
    for input, value in var.diagnostic_settings[each.key] : input => value
    if !contains(local.diagnostic_setting_ignored_inputs, input)
  }
  response_export_values = []
  retry                  = var.retry

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }
}

resource "azapi_resource" "role_assignments" {
  for_each = module.avm_interfaces.role_assignments_azapi

  type                 = var.resource_types.authorization_role_assignments
  name                 = each.value.name
  parent_id            = var.resource_id
  body                 = each.value.body
  ignore_body_changes  = length(var.ignore_body_changes.authorization_role_assignments) > 0 ? var.ignore_body_changes.authorization_role_assignments : null
  ignore_casing        = true
  ignore_null_property = true
  # An existing role assignment cannot be changed (RoleAssignmentUpdateNotPermitted), so a new principal,
  # role or delegated identity replaces it. So does a cleared condition or description: the body drops
  # the null (ignore_null_property) and the change would not reach Azure. A changed explicit name
  # replaces it too, despite `ignore_changes = [name]` below; a generated name stays null here.
  replace_triggers_external_values = {
    condition                              = var.role_assignments[each.key].condition
    condition_version                      = var.role_assignments[each.key].condition_version
    delegated_managed_identity_resource_id = var.role_assignments[each.key].delegated_managed_identity_resource_id
    description                            = var.role_assignments[each.key].description
    name                                   = var.role_assignments[each.key].name
    principal_id                           = lower(var.role_assignments[each.key].principal_id)
    role_definition_id_or_name             = lower(var.role_assignments[each.key].role_definition_id_or_name)
  }
  response_export_values = []
  retry                  = var.retry

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }

  lifecycle {
    ignore_changes = [name] # random UUID names; keeps imported names stable

    # A role name not found in the lookup scope is passed through as it is, and Azure would only reject
    # it during apply.
    precondition {
      condition     = startswith(each.value.body.properties.roleDefinitionId, "/")
      error_message = "role_assignments.${each.key}: `${var.role_assignments[each.key].role_definition_id_or_name}` is not a role definition ID, and no role of that name exists in ${coalesce(var.role_assignment_definition_scope, var.resource_id)}."
    }
  }
}

resource "azapi_resource" "lock" {
  count = var.lock != null ? 1 : 0

  type                   = var.resource_types.authorization_locks
  name                   = coalesce(module.avm_interfaces.lock_azapi.name, "lock-${var.lock.kind}")
  parent_id              = var.resource_id
  body                   = module.avm_interfaces.lock_azapi.body
  ignore_body_changes    = length(var.ignore_body_changes.authorization_locks) > 0 ? var.ignore_body_changes.authorization_locks : null
  ignore_null_property   = true
  response_export_values = []
  retry                  = var.retry

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }

  # Created last and removed first: a lock also blocks writes to what sits under the resource.
  depends_on = [time_sleep.lock_removal]

  lifecycle {
    replace_triggered_by = [time_sleep.lock_removal[count.index]]
  }
}

# Azure keeps enforcing a deleted lock for a few seconds. Destroyed after the lock and before everything
# else, this pause lets the deletion propagate first. Its triggers replace it, and through
# replace_triggered_by the lock, whenever the resource is replaced, its diagnostic settings or role
# assignments change (including which diagnostic settings inputs are ignored, which recreates them), or
# the caller's lock_dependencies change: a lock also blocks deleting those (ScopeLocked). The order is
# then lock removed, pause, changes, lock created again. New children are in that order too, which a
# ReadOnly lock needs: Terraform orders the creates of a destroyed resource's dependencies after that
# destroy.
#
# To replace a child without an input change (-replace, a tainted instance), replace this pause in the
# same run: `-replace='module.interfaces.time_sleep.lock_removal[0]'`. A replace_triggered_by on the
# children cannot do it: Terraform fails with "no change found" whenever a collection has no instances.
resource "time_sleep" "lock_removal" {
  count = var.lock != null ? 1 : 0

  destroy_duration = "30s"
  triggers = {
    resource_id       = var.resource_id
    children          = local.lock_children
    lock_dependencies = sha256(jsonencode(var.lock_dependencies))
  }

  depends_on = [
    azapi_resource.diagnostic_settings,
    azapi_resource.role_assignments,
  ]
}

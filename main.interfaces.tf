module "interfaces" {
  source  = "Azure/avm-utl-interfaces/azure"
  version = "0.9.0"

  enable_telemetry = false # defaults to true
  location         = var.location
  lock             = var.lock
  role_assignments = local.role_assignments
  # Role definitions are looked up by name in the resource group, which exists before the identity, so
  # an unknown role name fails during plan.
  role_assignment_definition_scope = var.parent_id
}

resource "azapi_resource" "role_assignments" {
  for_each = module.interfaces.role_assignments_azapi

  type                 = var.resource_types.authorization_role_assignments
  name                 = each.value.name
  parent_id            = azapi_resource.this.id
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
  }
}

resource "azapi_resource" "lock" {
  count = var.lock != null ? 1 : 0

  type                   = var.resource_types.authorization_locks
  name                   = coalesce(module.interfaces.lock_azapi.name, "lock-${var.lock.kind}")
  parent_id              = azapi_resource.this.id
  body                   = module.interfaces.lock_azapi.body
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

  # Created last and removed first: a lock also blocks writes to the resources under the identity.
  depends_on = [time_sleep.lock_removal]

  lifecycle {
    replace_triggered_by = [time_sleep.lock_removal[count.index]]
  }
}

# Azure keeps enforcing a deleted lock for a few seconds. Destroyed after the lock and before everything
# else, this pause lets the deletion propagate first. Its triggers replace it, and through
# replace_triggered_by the lock, whenever the identity is replaced or its credentials or role
# assignments change: a lock also blocks deleting those (ScopeLocked). The order is then lock removed,
# pause, changes, lock created again.
resource "time_sleep" "lock_removal" {
  count = var.lock != null ? 1 : 0

  destroy_duration = "30s"
  triggers = {
    identity_id = azapi_resource.this.id
    children    = sha256(jsonencode([var.federated_identity_credentials, var.role_assignments]))
  }

  depends_on = [
    azapi_resource.this,
    azapi_resource.role_assignments,
    module.federated_identity_credential,
  ]
}

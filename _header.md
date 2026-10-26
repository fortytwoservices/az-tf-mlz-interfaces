# az-tf-mlz-interfaces

The standard interfaces for Fortytwo's managed landing zone (MLZ) modules, in AzAPI: a lock, role
assignments and diagnostic settings on any Azure resource. Every `az-tf-mlz-*` module calls it for its
primary resource (and its submodules for theirs), so this behaviour is written, tested and fixed once.
Request bodies come from `Azure/avm-utl-interfaces/azure` (telemetry off); the variables are the Azure
Verified Modules (AVM) interface declarations.

```hcl
module "interfaces" {
  source = "git::https://github.com/fortytwoservices/az-tf-mlz-interfaces.git?ref=vX.Y.Z"

  resource_id                      = azapi_resource.this.id
  location                         = var.location
  role_assignment_definition_scope = var.parent_id # the resource group: role names fail during plan
  lock                             = var.lock
  role_assignments                 = var.role_assignments
  diagnostic_settings              = var.diagnostic_settings
  lock_dependencies                = { for key, child in module.child : key => child.lock_dependency }
  resource_types                   = var.resource_types # its three interface keys are read
  ignore_body_changes              = var.ignore_body_changes
  retry                            = var.retry
  timeouts                         = var.timeouts
}
```

What it handles, so that changes reach Azure:

- **Role assignments** are replaced when the principal, role, delegated identity, condition, condition
  version, description or an explicit name changes (Azure cannot update them in place). Role names are
  resolved in `role_assignment_definition_scope`, and a name not found there fails the plan; tenant-level
  role definition IDs are qualified with the subscription, as Azure returns them.
- **Diagnostic settings** match log entries by category and ignore the disabled categories Azure adds,
  so the next plan is clean; any change to a setting recreates it, so removed destinations and
  categories really go. Inputs at a path in `ignore_body_changes` are left out of that, so changing
  which inputs are ignored recreates the setting once.
- **The lock** is created last and removed first, followed by a 30-second pause while Azure stops
  enforcing it. Because a lock blocks deleting what sits under the resource, any change to the role
  assignments, the diagnostic settings or `lock_dependencies` (the caller's own child resources) removes
  the lock, makes the change and locks again. Azure applies the lock to the children's own interfaces
  too, so a submodule that calls this module outputs its `lock_dependency`, and the parent passes that
  in `lock_dependencies` (the child's ID is enough for a child without interfaces). To force-replace one
  of them (`-replace`), also replace `module.interfaces.time_sleep.lock_removal[0]` in the same run. New
  children are created only after the lock is removed, which matters under `ReadOnly`: it also blocks
  creating them. A `ReadOnly` lock also blocks changes to the resource itself, which do not cycle it:
  set `lock = null`, apply your change, then lock again.

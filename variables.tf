variable "location" {
  type        = string
  description = "Azure region of the resource, for example `norwayeast`. Passed to `Azure/avm-utl-interfaces/azure`, which requires it."
  nullable    = false
}

variable "resource_id" {
  type        = string
  description = "Resource ID of the resource the lock, role assignments and diagnostic settings are created on."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/(subscriptions|providers)/", var.resource_id))
    error_message = "`resource_id` must be an Azure resource ID, starting with /subscriptions/ or /providers/."
  }
}

variable "lock_dependencies" {
  type        = map(string)
  default     = {}
  description = <<DESCRIPTION
The calling module's own child resources under `resource_id`, by any stable key, as values that change whenever a child is created, replaced or changed. Azure applies the lock to them too: it blocks deleting them, and a `ReadOnly` lock also blocks updating them in place, which keeps their IDs. So each submodule outputs a `lock_dependency`, a hash of its ID and body (plus, if it calls this module, this module's `lock_dependency` output), and the parent passes `{ for key, child in module.child : key => child.lock_dependency }`. A bare ID covers only deletes and replacements. A change to this map recreates the lock around it: lock removed, 30-second pause, changes, lock created again. The lock is also created after them and removed before them.
DESCRIPTION
  nullable    = false
}

variable "role_assignment_definition_scope" {
  type        = string
  default     = null
  description = "(Optional) Scope in which role names in `role_assignments` are looked up, usually the resource group of `resource_id`: it exists before the resource, so an unknown role name fails during plan. Defaults to `resource_id`."
}

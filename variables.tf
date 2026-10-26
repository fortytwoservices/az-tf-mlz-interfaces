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
    condition     = can(regex("^/(subscriptions|providers)/", var.resource_id))
    error_message = "`resource_id` must be an Azure resource ID, starting with /subscriptions/ or /providers/."
  }
}

variable "lock_dependencies" {
  type        = map(string)
  default     = {}
  description = <<DESCRIPTION
IDs of the calling module's own child resources under `resource_id`, by any stable key, for example `{ for key, credential in module.credential : key => credential.resource_id }`. A lock also blocks deleting them, so a change to this map recreates the lock around it: lock removed, 30-second pause, changes, lock created again. The lock is also created after them and removed before them.
DESCRIPTION
  nullable    = false
}

variable "role_assignment_definition_scope" {
  type        = string
  default     = null
  description = "(Optional) Scope in which role names in `role_assignments` are looked up, usually the resource group of `resource_id`: it exists before the resource, so an unknown role name fails during plan. Defaults to `resource_id`."
}

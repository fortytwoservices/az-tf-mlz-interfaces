output "diagnostic_setting_resource_ids" {
  description = "Resource IDs of the diagnostic settings, by key."
  value       = { for key, setting in azapi_resource.diagnostic_settings : key => setting.id }
}

output "lock_dependency" {
  description = "Changes whenever the resource, these interfaces or `lock_dependencies` change. A submodule outputs it, and its parent passes it in the parent's own `lock_dependencies`: Azure applies the parent's lock to these interfaces too, so it has to be removed around their changes."
  value = sha256(jsonencode([
    var.resource_id,
    local.lock_children,
    var.lock_dependencies,
    # References, so a parent's lock is created after these and removed before them.
    values(azapi_resource.diagnostic_settings)[*].id,
    values(azapi_resource.role_assignments)[*].id,
  ]))
}

output "lock_resource_id" {
  description = "Resource ID of the lock, or null without `lock`."
  value       = try(azapi_resource.lock[0].id, null)
}

output "role_assignment_resource_ids" {
  description = "Resource IDs of the role assignments, by key."
  value       = { for key, assignment in azapi_resource.role_assignments : key => assignment.id }
}

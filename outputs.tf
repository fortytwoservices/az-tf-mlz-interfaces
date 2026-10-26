output "diagnostic_setting_resource_ids" {
  description = "Resource IDs of the diagnostic settings, by key."
  value       = { for key, setting in azapi_resource.diagnostic_settings : key => setting.id }
}

output "lock_resource_id" {
  description = "Resource ID of the lock, or null without `lock`."
  value       = try(azapi_resource.lock[0].id, null)
}

output "role_assignment_resource_ids" {
  description = "Resource IDs of the role assignments, by key."
  value       = { for key, assignment in azapi_resource.role_assignments : key => assignment.id }
}

output "name" {
  description = "Name of the federated identity credential."
  value       = azapi_resource.this.name
}

output "resource_id" {
  description = "Resource ID of the federated identity credential."
  value       = azapi_resource.this.id
}

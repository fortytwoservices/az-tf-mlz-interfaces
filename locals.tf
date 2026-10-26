locals {
  role_assignments = {
    for key, assignment in var.role_assignments : key => merge(assignment, {
      # With principalType set, ARM does not fail with PrincipalNotFound while a new service principal is
      # still replicating (Microsoft Learn, "Troubleshoot Azure RBAC").
      principal_type = assignment.principal_type == null && assignment.skip_service_principal_aad_check ? "ServicePrincipal" : assignment.principal_type
      # Azure returns role definition IDs qualified with the subscription (as found in AVM NSG 0.6.0);
      # qualify tenant-level IDs the same way so the next plan is clean. Management-group-scoped IDs
      # (/providers/Microsoft.Management/...) are passed through unchanged.
      role_definition_id_or_name = startswith(lower(assignment.role_definition_id_or_name), "/providers/microsoft.authorization/roledefinitions/") ? "/subscriptions/${local.subscription_id}${assignment.role_definition_id_or_name}" : assignment.role_definition_id_or_name
    })
  }
  subscription_id = provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", var.parent_id).subscription_id
}

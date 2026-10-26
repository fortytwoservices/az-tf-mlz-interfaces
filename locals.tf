locals {
  role_assignments = {
    for key, assignment in var.role_assignments : key => merge(assignment, {
      # With principalType set, ARM does not fail with PrincipalNotFound while a new service principal is
      # still replicating (Microsoft Learn, "Troubleshoot Azure RBAC").
      principal_type = assignment.principal_type == null && assignment.skip_service_principal_aad_check ? "ServicePrincipal" : assignment.principal_type
      # Azure returns role definition IDs qualified with the subscription (as found in AVM NSG 0.6.0);
      # qualify tenant-level IDs the same way so the next plan is clean. Management-group-scoped IDs
      # (/providers/Microsoft.Management/...) and resources outside a subscription are left alone.
      role_definition_id_or_name = local.subscription_id != null && startswith(lower(assignment.role_definition_id_or_name), "/providers/microsoft.authorization/roledefinitions/") ? "/subscriptions/${local.subscription_id}${assignment.role_definition_id_or_name}" : assignment.role_definition_id_or_name
    })
  }
  subscription_id = try(regex("(?i)^/subscriptions/([^/]+)", var.resource_id)[0], null)

  # The body path each diagnostic_settings input is sent to (Azure/avm-utl-interfaces/azure 0.9.0).
  diagnostic_setting_body_paths = {
    event_hub_authorization_rule_resource_id = "properties.eventHubAuthorizationRuleId"
    event_hub_name                           = "properties.eventHubName"
    log_analytics_destination_type           = "properties.logAnalyticsDestinationType"
    logs                                     = "properties.logs"
    marketplace_partner_resource_id          = "properties.marketplacePartnerId"
    metrics                                  = "properties.metrics"
    storage_account_resource_id              = "properties.storageAccountId"
    workspace_resource_id                    = "properties.workspaceId"
  }
  # Changes whenever the children under the lock change, including which diagnostic settings inputs are
  # ignored, which recreates those settings (see time_sleep.lock_removal).
  lock_children = sha256(jsonencode([var.diagnostic_settings, var.role_assignments, local.diagnostic_setting_ignored_inputs]))
  # Inputs whose body path is ignored (the path itself, a parent or a child of it in ignore_body_changes)
  # stay out of the diagnostic settings' replacement trigger, so changing them does not reach Azure either.
  diagnostic_setting_ignored_inputs = [
    for input, path in local.diagnostic_setting_body_paths : input
    if anytrue([
      for ignored in var.ignore_body_changes.insights_diagnostic_settings :
      ignored == path || startswith(path, "${ignored}.") || startswith(ignored, "${path}.")
    ])
  ]
}

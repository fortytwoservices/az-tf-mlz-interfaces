# Real Azure, no mocks: ARM_SUBSCRIPTION_ID=<test subscription> terraform test -test-directory=tests/integration
# Proves what mocks cannot: credentials written in parallel are serialised, survive an update of the
# identity, and the lock is removed before everything else on destroy.

run "setup" {
  module {
    source = "./tests/integration/setup"
  }
}

run "create" {
  variables {
    name      = "id-mlz-it-${run.setup.suffix}"
    parent_id = run.setup.resource_group_id
    location  = run.setup.location
    federated_identity_credentials = {
      one   = { issuer = "https://token.actions.githubusercontent.com", subject = "repo:example-org/example-repo:environment:one" }
      two   = { issuer = "https://token.actions.githubusercontent.com", subject = "repo:example-org/example-repo:environment:two" }
      three = { issuer = "https://token.actions.githubusercontent.com", subject = "repo:example-org/example-repo:environment:three" }
    }
    lock = { kind = "CanNotDelete" }
    role_assignments = {
      reader = { role_definition_id_or_name = "Reader", principal_id = run.setup.object_id }
    }
  }

  assert {
    condition     = length(output.federated_identity_credential_resource_ids) == 3
    error_message = "All three credentials should be created."
  }
  assert {
    condition     = can(regex("^[0-9a-f-]{36}$", output.principal_id)) && can(regex("^[0-9a-f-]{36}$", output.client_id))
    error_message = "principal_id and client_id should be read back from Azure."
  }
}

run "update_identity" {
  variables {
    name      = "id-mlz-it-${run.setup.suffix}"
    parent_id = run.setup.resource_group_id
    location  = run.setup.location
    federated_identity_credentials = {
      one   = { issuer = "https://token.actions.githubusercontent.com", subject = "repo:example-org/example-repo:environment:one" }
      two   = { issuer = "https://token.actions.githubusercontent.com", subject = "repo:example-org/example-repo:environment:two" }
      three = { issuer = "https://token.actions.githubusercontent.com", subject = "repo:example-org/example-repo:environment:three" }
    }
    lock = { kind = "CanNotDelete" }
    role_assignments = {
      reader = { role_definition_id_or_name = "Reader", principal_id = run.setup.object_id }
    }
    isolation_scope = "Regional"
    tags            = { updated = "true" } # a PUT of the identity without its credentials
  }

  assert {
    condition     = azapi_resource.this.tags == tomap({ updated = "true" })
    error_message = "The identity should be updated in place."
  }
}

run "credentials_survive" {
  module {
    source = "./tests/integration/read"
  }

  variables {
    credential_ids = run.update_identity.federated_identity_credential_resource_ids
  }

  assert {
    condition     = output.subjects.two == "repo:example-org/example-repo:environment:two" && length(output.subjects) == 3
    error_message = "The credentials should still exist after the identity was updated."
  }
}

run "isolation_scope_set_in_azure" {
  module {
    source = "./tests/integration/read_identity"
  }

  variables {
    identity_id = run.update_identity.resource_id
  }

  assert {
    condition     = output.isolation_scope == "Regional"
    error_message = "Azure should report the Regional isolation scope set by update_identity."
  }
}

run "remove_credential_under_lock" {
  # A credential is deleted while the lock stays configured: the lock is removed and created again
  # around the change. The scope goes back to Azure's default, which must reach Azure.
  variables {
    name      = "id-mlz-it-${run.setup.suffix}"
    parent_id = run.setup.resource_group_id
    location  = run.setup.location
    federated_identity_credentials = {
      one = { issuer = "https://token.actions.githubusercontent.com", subject = "repo:example-org/example-repo:environment:one" }
      two = { issuer = "https://token.actions.githubusercontent.com", subject = "repo:example-org/example-repo:environment:two" }
    }
    lock = { kind = "CanNotDelete" }
    role_assignments = {
      reader = { role_definition_id_or_name = "Reader", principal_id = run.setup.object_id }
    }
  }

  assert {
    condition     = keys(output.federated_identity_credential_resource_ids) == ["one", "two"] && length(azapi_resource.lock) == 1
    error_message = "The third credential should be gone and the lock back."
  }
}

run "isolation_scope_reset_in_azure" {
  module {
    source = "./tests/integration/read_identity"
  }

  variables {
    identity_id = run.remove_credential_under_lock.resource_id
  }

  assert {
    condition     = output.isolation_scope == "None"
    error_message = "Azure should report the default isolation scope again once isolation_scope is no longer set."
  }
}

run "replace_locked_identity" {
  # A new name replaces the identity. The lock goes first and the pause is replaced with the identity,
  # so the old identity is deleted only after the lock deletion has propagated.
  variables {
    name      = "id-mlz-it-${run.setup.suffix}-renamed"
    parent_id = run.setup.resource_group_id
    location  = run.setup.location
    federated_identity_credentials = {
      one = { issuer = "https://token.actions.githubusercontent.com", subject = "repo:example-org/example-repo:environment:one" }
    }
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = output.name == "id-mlz-it-${run.setup.suffix}-renamed" && azapi_resource.lock[0].parent_id == output.resource_id
    error_message = "The identity should be replaced and locked again."
  }
}

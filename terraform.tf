terraform {
  # 1.11 is the first release with write-only arguments (`ignore_body_changes`, `sensitive_body`).
  required_version = ">= 1.11, < 2.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    # random ~> 3.6 comes with avm-utl-interfaces (role assignment names).
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}

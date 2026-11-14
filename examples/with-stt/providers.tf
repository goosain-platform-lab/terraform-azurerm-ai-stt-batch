# Authentication comes from the environment: HCP Terraform dynamic credentials
# (OIDC) in CI, or `az login` locally. ARM_SUBSCRIPTION_ID selects the
# subscription. No client secret is used anywhere.
provider "azurerm" {
  # Use Entra ID (not shared keys) for any storage data-plane call.
  storage_use_azuread = true

  # azurerm 5.x registers nothing by default; register only what this needs.
  resource_providers_to_register = [
    "Microsoft.ServiceBus",
    "Microsoft.Sql",
    "Microsoft.AlertsManagement",
    "Microsoft.CognitiveServices",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.Storage",
    "Microsoft.Web",
  ]

  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    cognitive_account {
      purge_soft_delete_on_destroy = true
    }

    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

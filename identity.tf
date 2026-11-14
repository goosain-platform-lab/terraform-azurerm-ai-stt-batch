# The Function App's user-assigned identity. All access is RBAC: no keys,
# SAS tokens or connection strings.
resource "azurerm_user_assigned_identity" "this" {
  name                = local.names.identity
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

locals {
  role_assignments = merge(
    {
      speech_user = {
        scope = var.speech_account_id
        role  = "Cognitive Services Speech User"
      }
      translator_user = {
        scope = var.translator_account_id
        role  = "Cognitive Services User"
      }
      data_blob = {
        scope = var.data_storage_account_id
        role  = "Storage Blob Data Contributor"
      }
      sb_sender = {
        scope = azurerm_servicebus_namespace.this.id
        role  = "Azure Service Bus Data Sender"
      }
      sb_receiver = {
        scope = azurerm_servicebus_namespace.this.id
        role  = "Azure Service Bus Data Receiver"
      }
      # The Functions host needs blob, queue and table access to its own account.
      func_blob = {
        scope = azurerm_storage_account.func.id
        role  = "Storage Blob Data Owner"
      }
      func_queue = {
        scope = azurerm_storage_account.func.id
        role  = "Storage Queue Data Contributor"
      }
      func_table = {
        scope = azurerm_storage_account.func.id
        role  = "Storage Table Data Contributor"
      }
      appi_publisher = {
        scope = azurerm_application_insights.this.id
        role  = "Monitoring Metrics Publisher"
      }
    },
    var.summarization_enabled ? {
      openai_user = {
        scope = azurerm_cognitive_account.openai[0].id
        role  = "Cognitive Services OpenAI User"
      }
    } : {},
    var.use_key_vault ? {
      kv_secrets = {
        scope = var.key_vault_id
        role  = "Key Vault Secrets User"
      }
    } : {}
  )
}

resource "azurerm_role_assignment" "identity" {
  for_each = local.role_assignments

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
}

# Batch transcription is run by the Speech service itself, which fetches the
# audio with its own managed identity.
resource "azurerm_role_assignment" "speech_reads_audio" {
  scope                = var.data_storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.speech_principal_id
  principal_type       = "ServicePrincipal"
}

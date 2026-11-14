# .NET 8 isolated Function App that runs the pipeline:
# queue message -> transcribe (Speech) -> translate (Translator) ->
# summarise (Azure OpenAI) -> store results (SQL + blob).
resource "azurerm_service_plan" "this" {
  count = var.create_app_service_plan ? 1 : 0

  name                = local.names.plan
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Windows"
  sku_name            = var.app_service_plan_sku
  tags                = var.tags
}

resource "azurerm_application_insights" "this" {
  name                         = local.names.app_insights
  location                     = var.location
  resource_group_name          = var.resource_group_name
  application_type             = "web"
  workspace_id                 = var.log_analytics_workspace_id
  local_authentication_enabled = false
  tags                         = var.tags
}

locals {
  client_id = azurerm_user_assigned_identity.this.client_id

  # Non-secret settings: endpoints and names only. Every service is reached with
  # the managed identity named by AZURE_CLIENT_ID.
  function_settings = merge(
    {
      AZURE_CLIENT_ID                           = local.client_id
      APPLICATIONINSIGHTS_AUTHENTICATION_STRING = "Authorization=AAD;ClientId=${local.client_id}"

      # Identity-based host storage and Service Bus trigger.
      AzureWebJobsStorage__credential               = "managedidentity"
      AzureWebJobsStorage__clientId                 = local.client_id
      ServiceBusConnection__fullyQualifiedNamespace = local.service_bus_fqdn
      ServiceBusConnection__credential              = "managedidentity"
      ServiceBusConnection__clientId                = local.client_id

      Speech__Endpoint        = var.speech_endpoint
      Speech__ResourceId      = var.speech_account_id
      Speech__Region          = var.location
      Translator__Endpoint    = var.translator_endpoint
      Translator__Region      = var.location
      Storage__BlobServiceUri = var.data_blob_endpoint
      Sql__ConnectionString   = "Server=tcp:${azurerm_mssql_server.this.fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.this.name};Authentication=Active Directory Managed Identity;User Id=${local.client_id};Encrypt=True;"
    },
    { for q in var.service_bus_queues : "Queues__${replace(q, "-", "_")}" => q },
    var.summarization_enabled ? {
      OpenAI__Endpoint = azurerm_cognitive_account.openai[0].endpoint
    } : {},
    var.use_key_vault ? {
      for setting, secret in var.key_vault_references :
      setting => "@Microsoft.KeyVault(VaultName=${local.key_vault_name};SecretName=${secret})"
    } : {}
  )
}

resource "azurerm_windows_function_app" "this" {
  name                                           = local.names.function
  location                                       = var.location
  resource_group_name                            = var.resource_group_name
  service_plan_id                                = local.plan_id
  https_only                                     = true
  public_network_access_enabled                  = var.function_public_network_access_enabled
  virtual_network_subnet_id                      = var.app_subnet_id
  key_vault_reference_identity_id                = azurerm_user_assigned_identity.this.id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  functions_extension_version                    = "~4"
  tags                                           = var.tags

  # Identity-based host storage: no AzureWebJobsStorage connection string.
  storage_account_name          = azurerm_storage_account.func.name
  storage_uses_managed_identity = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  site_config {
    # Keeps the Service Bus trigger listening on a dedicated plan.
    always_on                              = true
    vnet_route_all_enabled                 = true
    use_32_bit_worker                      = false
    minimum_tls_version                    = "1.2"
    ftps_state                             = "Disabled"
    application_insights_connection_string = azurerm_application_insights.this.connection_string

    application_stack {
      dotnet_version              = "v8.0"
      use_dotnet_isolated_runtime = true
    }
  }

  app_settings = local.function_settings

  depends_on = [azurerm_role_assignment.identity]
}

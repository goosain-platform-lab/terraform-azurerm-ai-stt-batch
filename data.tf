#------------------------------------------------------------------------------
# Functions host storage (identity-based, private)
#------------------------------------------------------------------------------
resource "azurerm_storage_account" "func" {
  name                             = local.names.storage_func
  location                         = var.location
  resource_group_name              = var.resource_group_name
  account_kind                     = "StorageV2"
  account_tier                     = "Standard"
  account_replication_type         = var.storage_replication_type
  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false
  local_user_enabled               = false
  public_network_access            = "Disabled"
  tags                             = var.tags

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

#------------------------------------------------------------------------------
# Service Bus: one queue per pipeline stage, plus a topic for notifications.
# Local (SAS) auth is disabled.
#------------------------------------------------------------------------------
resource "azurerm_servicebus_namespace" "this" {
  name                          = local.names.service_bus
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = var.service_bus_sku
  capacity                      = local.service_bus_private ? var.service_bus_capacity : 0
  premium_messaging_partitions  = local.service_bus_private ? 1 : 0
  local_auth_enabled            = false
  public_network_access_enabled = !local.service_bus_private
  minimum_tls_version           = "1.2"
  tags                          = var.tags
}

resource "azurerm_servicebus_queue" "this" {
  for_each = toset(var.service_bus_queues)

  name                                    = each.value
  namespace_id                            = azurerm_servicebus_namespace.this.id
  lock_duration                           = "PT1M"
  max_delivery_count                      = 10
  default_message_ttl                     = "P14D"
  duplicate_detection_history_time_window = "PT10M"
  dead_lettering_on_message_expiration    = true
  batched_operations_enabled              = true
}

resource "azurerm_servicebus_topic" "this" {
  for_each = var.service_bus_topic_subscriptions

  name                         = each.key
  namespace_id                 = azurerm_servicebus_namespace.this.id
  default_message_ttl          = "P14D"
  requires_duplicate_detection = true
}

resource "azurerm_servicebus_subscription" "this" {
  for_each = local.topic_subscriptions

  name               = each.value.name
  topic_id           = azurerm_servicebus_topic.this[each.value.topic].id
  max_delivery_count = 10
}

#------------------------------------------------------------------------------
# Azure SQL: Entra-only, no SQL login or password. The identity is added as a
# database user after deployment (see README).
#------------------------------------------------------------------------------
resource "azurerm_mssql_server" "this" {
  name                              = local.names.sql_server
  location                          = var.location
  resource_group_name               = var.resource_group_name
  version                           = "12.0"
  minimum_tls_version               = "1.2"
  public_network_access_enabled     = false
  primary_user_assigned_identity_id = azurerm_user_assigned_identity.this.id
  tags                              = var.tags

  azuread_administrator {
    login_username              = local.sql_admin.login_username
    object_id                   = local.sql_admin.object_id
    azuread_authentication_only = true
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }
}

resource "azurerm_mssql_database" "this" {
  name                 = local.names.sql_database
  server_id            = azurerm_mssql_server.this.id
  sku_name             = var.sql_database_sku
  max_size_gb          = 2
  storage_account_type = var.sql_backup_storage_redundancy
  tags                 = var.tags
}

#------------------------------------------------------------------------------
# Azure OpenAI for summaries (optional, keys disabled, private)
#------------------------------------------------------------------------------
resource "azurerm_cognitive_account" "openai" {
  count = var.summarization_enabled ? 1 : 0

  name                          = local.names.openai
  location                      = local.openai_location
  resource_group_name           = var.resource_group_name
  kind                          = "OpenAI"
  sku_name                      = var.openai_sku
  custom_subdomain_name         = local.names.openai
  local_auth_enabled            = false
  public_network_access_enabled = false
  tags                          = var.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_cognitive_deployment" "openai" {
  for_each = var.summarization_enabled ? var.openai_deployments : {}

  name                 = each.key
  cognitive_account_id = azurerm_cognitive_account.openai[0].id

  model {
    format  = "OpenAI"
    name    = each.value.model_name
    version = each.value.model_version
  }

  sku {
    name     = each.value.sku_name
    capacity = each.value.capacity
  }
}

locals {
  private_endpoints = merge(
    {
      st-func-blob = {
        resource_id = azurerm_storage_account.func.id
        subresource = "blob"
        dns_zone    = "blob"
      }
      st-func-file = {
        resource_id = azurerm_storage_account.func.id
        subresource = "file"
        dns_zone    = "file"
      }
      st-func-queue = {
        resource_id = azurerm_storage_account.func.id
        subresource = "queue"
        dns_zone    = "queue"
      }
      st-func-table = {
        resource_id = azurerm_storage_account.func.id
        subresource = "table"
        dns_zone    = "table"
      }
      sql = {
        resource_id = azurerm_mssql_server.this.id
        subresource = "sqlServer"
        dns_zone    = "sql"
      }
      func = {
        resource_id = azurerm_windows_function_app.this.id
        subresource = "sites"
        dns_zone    = "sites"
      }
    },
    local.service_bus_private ? {
      sb = {
        resource_id = azurerm_servicebus_namespace.this.id
        subresource = "namespace"
        dns_zone    = "servicebus"
      }
    } : {},
    var.summarization_enabled ? {
      openai = {
        resource_id = azurerm_cognitive_account.openai[0].id
        subresource = "account"
        dns_zone    = "openai"
      }
    } : {}
  )

  diagnostic_targets = merge(
    {
      service_bus = azurerm_servicebus_namespace.this.id
      sql         = azurerm_mssql_database.this.id
      function    = azurerm_windows_function_app.this.id
    },
    var.summarization_enabled ? { openai = azurerm_cognitive_account.openai[0].id } : {}
  )
}

resource "azurerm_private_endpoint" "this" {
  for_each = local.private_endpoints

  name                          = "pe-${each.key}-${local.base}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  subnet_id                     = var.private_endpoint_subnet_id
  custom_network_interface_name = "nic-pe-${each.key}-${local.base}"
  tags                          = var.tags

  private_service_connection {
    name                           = "psc-${each.key}-${local.base}"
    private_connection_resource_id = each.value.resource_id
    subresource_names              = [each.value.subresource]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_ids[each.value.dns_zone]]
  }
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = local.diagnostic_targets

  name                       = "diag-to-law"
  target_resource_id         = each.value
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}

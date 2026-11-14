output "identity" {
  description = "User-assigned identity used by the Function App."
  value = {
    id           = azurerm_user_assigned_identity.this.id
    client_id    = azurerm_user_assigned_identity.this.client_id
    principal_id = azurerm_user_assigned_identity.this.principal_id
    name         = azurerm_user_assigned_identity.this.name
  }
}

output "function_app" {
  description = "Function App name and host name."
  value = {
    name     = azurerm_windows_function_app.this.name
    hostname = azurerm_windows_function_app.this.default_hostname
  }
}

output "service_bus" {
  description = "Service Bus namespace and queues."
  value = {
    name   = azurerm_servicebus_namespace.this.name
    fqdn   = local.service_bus_fqdn
    queues = [for q in azurerm_servicebus_queue.this : q.name]
  }
}

output "sql" {
  description = "SQL names for the post-deployment user grant."
  value = {
    server   = azurerm_mssql_server.this.name
    fqdn     = azurerm_mssql_server.this.fully_qualified_domain_name
    database = azurerm_mssql_database.this.name
  }
}

output "openai_endpoint" {
  description = "Azure OpenAI endpoint (null when summarisation is off)."
  value       = var.summarization_enabled ? azurerm_cognitive_account.openai[0].endpoint : null
}

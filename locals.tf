data "azurerm_client_config" "current" {}

locals {
  region_codes = {
    southafricanorth   = "zan"
    southafricawest    = "zaw"
    westeurope         = "weu"
    northeurope        = "neu"
    swedencentral      = "sdc"
    uksouth            = "uks"
    francecentral      = "frc"
    germanywestcentral = "gwc"
    switzerlandnorth   = "szn"
    eastus             = "eus"
    eastus2            = "eus2"
  }

  region          = lookup(local.region_codes, var.location, var.location)
  openai_location = coalesce(var.openai_location, var.location)
  openai_region   = lookup(local.region_codes, local.openai_location, local.openai_location)

  # <type>-<workload>-<component>-<environment>-<region>[suffix]
  base = "${var.workload}-${var.component}-${var.environment}-${local.region}${var.unique_suffix}"

  names = {
    identity     = "id-${local.base}"
    app_insights = "appi-${local.base}"
    plan         = "asp-${local.base}"
    function     = "func-${local.base}"
    service_bus  = "sbns-${local.base}"
    sql_server   = "sql-${local.base}"
    sql_database = "sqldb-${local.base}"
    openai       = "oai-${var.workload}-${var.component}-${var.environment}-${local.openai_region}${var.unique_suffix}"
    # Storage accounts: lowercase letters and digits only, max 24 characters.
    storage_func = substr("st${var.workload}${var.component}${var.environment}${local.region}${var.unique_suffix}", 0, 24)
  }

  plan_id = var.create_app_service_plan ? azurerm_service_plan.this[0].id : var.app_service_plan_id

  key_vault_name = var.use_key_vault ? element(split("/", var.key_vault_id), 8) : null

  sql_admin = var.sql_entra_admin != null ? var.sql_entra_admin : {
    login_username = "terraform-deployer"
    object_id      = data.azurerm_client_config.current.object_id
  }

  service_bus_private = var.service_bus_sku == "Premium"
  service_bus_fqdn    = "${azurerm_servicebus_namespace.this.name}.servicebus.windows.net"

  topic_subscriptions = merge([
    for topic, subs in var.service_bus_topic_subscriptions : {
      for sub in subs : "${topic}/${sub}" => { topic = topic, name = sub }
    }
  ]...)
}

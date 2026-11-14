# Batch pipeline deployed together with the real-time STT workload it plugs
# into: a small spoke network, private DNS, Log Analytics, the STT module
# (pinned release) and this module.
locals {
  region = lookup({
    southafricanorth = "zan"
    southafricawest  = "zaw"
    westeurope       = "weu"
    northeurope      = "neu"
    swedencentral    = "sdc"
    uksouth          = "uks"
  }, var.location, var.location)

  suffix = "${var.environment}-${local.region}${var.unique_suffix}"

  tags = merge({
    workload    = "stt"
    environment = var.environment
    managed_by  = "terraform"
    repo        = "terraform-azurerm-ai-stt-batch"
  }, var.tags)

  subnets = {
    app = cidrsubnet(var.address_space, 2, 0) # /28 App Service integration
    pe  = cidrsubnet(var.address_space, 1, 1) # /27 private endpoints
  }

  private_dns_zones = {
    blob       = "privatelink.blob.core.windows.net"
    file       = "privatelink.file.core.windows.net"
    queue      = "privatelink.queue.core.windows.net"
    table      = "privatelink.table.core.windows.net"
    vault      = "privatelink.vaultcore.azure.net"
    cognitive  = "privatelink.cognitiveservices.azure.com"
    openai     = "privatelink.openai.azure.com"
    sites      = "privatelink.azurewebsites.net"
    servicebus = "privatelink.servicebus.windows.net"
    sql        = "privatelink.database.windows.net"
  }
}

resource "azurerm_resource_group" "network" {
  name     = "rg-stt-network-${local.suffix}"
  location = var.location
  tags     = local.tags
}

# One resource group for both modules: the Function App shares the real-time
# workload's App Service plan, and an app must sit in its plan's resource group.
resource "azurerm_resource_group" "workload" {
  name     = "rg-stt-${local.suffix}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_log_analytics_workspace" "this" {
  name                         = "log-stt-${local.suffix}"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.workload.name
  sku                          = "PerGB2018"
  retention_in_days            = var.log_retention_days
  daily_quota_gb               = var.log_daily_quota_gb
  local_authentication_enabled = false
  tags                         = local.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-stt-${local.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.network.name
  address_space       = [var.address_space]
  tags                = local.tags
}

resource "azurerm_subnet" "app" {
  name                 = "snet-stt-app-${local.suffix}"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.subnets.app]

  delegation {
    name = "app-service"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "pe" {
  name                            = "snet-stt-pe-${local.suffix}"
  resource_group_name             = azurerm_resource_group.network.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [local.subnets.pe]
  default_outbound_access_enabled = false
}

resource "azurerm_network_security_group" "this" {
  for_each = local.subnets

  name                = "nsg-stt-${each.key}-${local.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.network.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.this["app"].id
}

resource "azurerm_subnet_network_security_group_association" "pe" {
  subnet_id                 = azurerm_subnet.pe.id
  network_security_group_id = azurerm_network_security_group.this["pe"].id
}

resource "azurerm_private_dns_zone" "this" {
  for_each = local.private_dns_zones

  name                = each.value
  resource_group_name = azurerm_resource_group.network.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = local.private_dns_zones

  name                 = "link-${each.key}-${local.suffix}"
  private_dns_zone_id  = azurerm_private_dns_zone.this[each.key].id
  virtual_network_id   = azurerm_virtual_network.this.id
  registration_enabled = false
  tags                 = local.tags
}

locals {
  dns_zone_ids = { for k, z in azurerm_private_dns_zone.this : k => z.id }
}

#------------------------------------------------------------------------------
# Real-time workload (pinned release of its own repo)
#------------------------------------------------------------------------------
module "stt" {
  source = "git::https://github.com/goosain-platform-lab/terraform-azurerm-ai-stt.git?ref=v0.1.0"

  environment         = var.environment
  location            = var.location
  unique_suffix       = var.unique_suffix
  resource_group_name = azurerm_resource_group.workload.name
  tags                = local.tags

  app_subnet_id              = azurerm_subnet.app.id
  private_endpoint_subnet_id = azurerm_subnet.pe.id
  private_dns_zone_ids       = local.dns_zone_ids
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.this,
    azurerm_subnet_network_security_group_association.app,
    azurerm_subnet_network_security_group_association.pe,
  ]
}

#------------------------------------------------------------------------------
# Batch pipeline (this module)
#------------------------------------------------------------------------------
module "stt_batch" {
  source = "../../"

  environment         = var.environment
  location            = var.location
  unique_suffix       = var.unique_suffix
  resource_group_name = azurerm_resource_group.workload.name
  tags                = local.tags

  app_subnet_id              = azurerm_subnet.app.id
  private_endpoint_subnet_id = azurerm_subnet.pe.id
  private_dns_zone_ids       = local.dns_zone_ids
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  speech_account_id       = module.stt.shared_services.speech_account_id
  speech_endpoint         = module.stt.shared_services.speech_endpoint
  speech_principal_id     = module.stt.shared_services.speech_principal_id
  translator_account_id   = module.stt.shared_services.translator_account_id
  translator_endpoint     = module.stt.shared_services.translator_endpoint
  data_storage_account_id = module.stt.shared_services.data_storage_account_id
  data_blob_endpoint      = module.stt.shared_services.data_blob_endpoint

  use_key_vault        = true
  key_vault_id         = module.stt.shared_services.key_vault_id
  key_vault_references = var.key_vault_references

  create_app_service_plan = false
  app_service_plan_id     = module.stt.shared_services.app_service_plan_id

  service_bus_sku       = var.service_bus_sku
  summarization_enabled = var.summarization_enabled
  openai_deployments    = var.openai_deployments
  sql_entra_admin       = var.sql_entra_admin
}

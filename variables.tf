#------------------------------------------------------------------------------
# Naming and placement
#------------------------------------------------------------------------------
variable "workload" {
  description = "Workload token used in resource names: <type>-<workload>-<component>-<environment>-<region>."
  type        = string
  default     = "stt"

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.workload))
    error_message = "workload must be 2-8 lowercase letters or digits."
  }
}

variable "component" {
  description = "Component token that sets these resources apart from the real-time workload."
  type        = string
  default     = "batch"

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.component))
    error_message = "component must be 2-6 lowercase letters or digits (it is also used in storage account names)."
  }
}

variable "environment" {
  description = "Environment token used in resource names."
  type        = string
  default     = "lab"
}

variable "location" {
  description = "Azure region (must match the real-time workload when sharing its App Service plan)."
  type        = string
}

variable "unique_suffix" {
  description = "Optional 0-4 character suffix for globally unique names."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9]{0,4}$", var.unique_suffix))
    error_message = "unique_suffix must be 0-4 lowercase letters or digits."
  }
}

variable "resource_group_name" {
  description = "Existing resource group for the batch resources. Must be the plan's resource group when sharing a plan."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

#------------------------------------------------------------------------------
# Network wiring
#------------------------------------------------------------------------------
variable "app_subnet_id" {
  description = "Subnet delegated to Microsoft.Web/serverFarms for the Function App's VNet integration."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Subnet that holds the private endpoints."
  type        = string
}

variable "private_dns_zone_ids" {
  description = "Private DNS zone IDs. Required keys: blob, file, queue, table, sites, servicebus, sql, openai. Extra keys are ignored."
  type        = map(string)

  validation {
    condition = alltrue([
      for k in ["blob", "file", "queue", "table", "sites", "servicebus", "sql", "openai"] :
      contains(keys(var.private_dns_zone_ids), k)
    ])
    error_message = "private_dns_zone_ids must contain blob, file, queue, table, sites, servicebus, sql and openai."
  }
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for diagnostics and Application Insights."
  type        = string
}

#------------------------------------------------------------------------------
# What this plugs into: the real-time workload's shared_services output
#------------------------------------------------------------------------------
variable "speech_account_id" {
  description = "Speech account the pipeline transcribes with."
  type        = string
}

variable "speech_endpoint" {
  description = "Speech account endpoint (custom subdomain)."
  type        = string
}

variable "speech_principal_id" {
  description = "Speech account's system-assigned identity. It is granted read access to the audio so batch transcription can fetch it."
  type        = string
}

variable "translator_account_id" {
  description = "Translator account the pipeline translates with."
  type        = string
}

variable "translator_endpoint" {
  description = "Translator account endpoint (custom subdomain)."
  type        = string
}

variable "data_storage_account_id" {
  description = "Storage account holding the audio and results."
  type        = string
}

variable "data_blob_endpoint" {
  description = "Blob endpoint of the data storage account."
  type        = string
}

variable "use_key_vault" {
  description = "Read secrets from the Key Vault in key_vault_id (grants the identity Key Vault Secrets User)."
  type        = bool
  default     = false
}

variable "key_vault_id" {
  description = "Key Vault to resolve key_vault_references from. Used when use_key_vault is true."
  type        = string
  default     = null

  validation {
    condition     = !var.use_key_vault || var.key_vault_id != null
    error_message = "Set key_vault_id when use_key_vault is true."
  }
}

variable "key_vault_references" {
  description = "Function app setting => Key Vault secret name. Terraform never sees the secret value."
  type        = map(string)
  default     = {}
}

variable "create_app_service_plan" {
  description = "Create a Windows plan for the Function App. Set false and pass app_service_plan_id to share the real-time workload's plan."
  type        = bool
  default     = true
}

variable "app_service_plan_id" {
  description = "Existing Windows plan to run on when create_app_service_plan is false. It must be in var.resource_group_name."
  type        = string
  default     = null

  validation {
    condition     = var.app_service_plan_id == null || try(lower(split("/", var.app_service_plan_id)[4]) == lower(var.resource_group_name), false)
    error_message = "app_service_plan_id must be in the same resource group as the Function App (var.resource_group_name)."
  }
}

#------------------------------------------------------------------------------
# Services (defaults are production-grade SKUs)
#------------------------------------------------------------------------------
variable "app_service_plan_sku" {
  description = "Windows plan SKU, used only when create_app_service_plan is true."
  type        = string
  default     = "B1"
}

variable "function_public_network_access_enabled" {
  description = "Allow public access to the Function App. Off by default: it is reached through its private endpoint."
  type        = bool
  default     = false
}

variable "service_bus_sku" {
  description = "Service Bus SKU. Premium supports private endpoints; Standard falls back to a public endpoint with Entra-only auth."
  type        = string
  default     = "Premium"

  validation {
    condition     = contains(["Standard", "Premium"], var.service_bus_sku)
    error_message = "service_bus_sku must be Standard or Premium."
  }
}

variable "service_bus_capacity" {
  description = "Messaging units for a Premium namespace."
  type        = number
  default     = 1
}

variable "service_bus_queues" {
  description = "One queue per pipeline stage."
  type        = list(string)
  default     = ["transcription-requests", "translation-requests", "summarization-requests", "pipeline-tasks"]
}

variable "service_bus_topic_subscriptions" {
  description = "Topic name => list of subscription names, for fan-out notifications."
  type        = map(list(string))
  default = {
    pipeline-events = ["default"]
  }
}

variable "summarization_enabled" {
  description = "Deploy an Azure OpenAI account for transcript summaries."
  type        = bool
  default     = true
}

variable "openai_location" {
  description = "Region for the Azure OpenAI account. Defaults to var.location."
  type        = string
  default     = null
}

variable "openai_sku" {
  description = "SKU for the Azure OpenAI account."
  type        = string
  default     = "S0"
}

variable "openai_deployments" {
  description = "Model deployments on the Azure OpenAI account. Empty by default so you choose a model available in your region."
  type = map(object({
    model_name    = string
    model_version = string
    sku_name      = optional(string, "GlobalStandard")
    capacity      = optional(number, 10)
  }))
  default = {}
}

variable "sql_database_sku" {
  description = "SKU for the SQL database."
  type        = string
  default     = "S0"
}

variable "sql_backup_storage_redundancy" {
  description = "Backup storage redundancy for the SQL database (Geo, Zone or Local)."
  type        = string
  default     = "Geo"
}

variable "sql_entra_admin" {
  description = "Entra ID group (recommended) or user that administers the SQL server. Null uses the identity running Terraform."
  type = object({
    login_username = string
    object_id      = string
  })
  default = null
}

variable "storage_replication_type" {
  description = "Replication for the Functions host storage account."
  type        = string
  default     = "LRS"
}

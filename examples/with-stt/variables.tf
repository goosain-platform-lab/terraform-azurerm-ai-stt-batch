variable "location" {
  description = "Azure region for the deployment."
  type        = string
  default     = "southafricanorth"
}

variable "environment" {
  description = "Environment token used in names."
  type        = string
  default     = "lab"
}

variable "unique_suffix" {
  description = "Optional 0-4 character suffix for globally unique names."
  type        = string
  default     = ""
}

variable "address_space" {
  description = "VNet address space (a /26 holds both workloads' private endpoints)."
  type        = string
  default     = "10.30.0.0/26"
}

variable "log_retention_days" {
  description = "Log Analytics retention."
  type        = number
  default     = 30
}

variable "log_daily_quota_gb" {
  description = "Daily ingestion cap in GB (-1 for no cap)."
  type        = number
  default     = 1
}

variable "service_bus_sku" {
  description = "Premium (private endpoint) or Standard (cheaper, public endpoint with Entra-only auth)."
  type        = string
  default     = "Premium"
}

variable "summarization_enabled" {
  description = "Deploy Azure OpenAI for transcript summaries."
  type        = bool
  default     = true
}

variable "openai_deployments" {
  description = "Azure OpenAI model deployments (see the module variable for the shape)."
  type = map(object({
    model_name    = string
    model_version = string
    sku_name      = optional(string, "GlobalStandard")
    capacity      = optional(number, 10)
  }))
  default = {}
}

variable "sql_entra_admin" {
  description = "Entra group (recommended) that administers SQL. Null uses the deploying identity."
  type = object({
    login_username = string
    object_id      = string
  })
  default = null
}

variable "key_vault_references" {
  description = "Function app setting => Key Vault secret name, for secrets an operator adds by hand."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Extra tags merged onto the defaults."
  type        = map(string)
  default     = {}
}

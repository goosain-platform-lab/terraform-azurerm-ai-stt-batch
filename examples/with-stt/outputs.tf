output "real_time" {
  description = "Real-time workload: apps and endpoints."
  value = {
    apps      = module.stt.apps
    endpoints = module.stt.endpoints
    key_vault = module.stt.key_vault
  }
}

output "batch" {
  description = "Batch pipeline: identity, Function App, Service Bus and SQL."
  value = {
    identity     = module.stt_batch.identity
    function_app = module.stt_batch.function_app
    service_bus  = module.stt_batch.service_bus
    sql          = module.stt_batch.sql
  }
}

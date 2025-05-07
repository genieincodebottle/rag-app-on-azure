# modules/api/outputs.tf

output "api_endpoint" {
  description = "URL of the API endpoint"
  value       = "https://${azurerm_api_management.main.name}.azure-api.net/${var.stage}"
}

output "api_id" {
  description = "ID of the API Management service"
  value       = azurerm_api_management.main.id
}

output "api_name" {
  description = "Name of the API Management service"
  value       = azurerm_api_management.main.name
}

output "gateway_url" {
  description = "Gateway URL of the API Management service"
  value       = azurerm_api_management.main.gateway_url
}

output "api_insights_id" {
  description = "ID of Application Insights for API Management"
  value       = azurerm_application_insights.api.id
}

output "api_insights_instrumentation_key" {
  description = "Instrumentation key for API Management Application Insights"
  value       = azurerm_application_insights.api.instrumentation_key
  sensitive   = true
}
# modules/monitoring/outputs.tf

output "action_group_id" {
  description = "ID of the Monitor Action Group"
  value       = azurerm_monitor_action_group.main.id
}

output "action_group_name" {
  description = "Name of the Monitor Action Group"
  value       = azurerm_monitor_action_group.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "dashboard_id" {
  description = "ID of the Azure Monitor Dashboard"
  value       = azurerm_portal_dashboard.main.id
}
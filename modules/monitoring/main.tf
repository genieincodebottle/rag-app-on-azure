# modules/monitoring/main.tf

# ================================================
# Monitoring Module for RAG System
# ================================================

# ==============================
# Locals
# ==============================

locals {
  name = "${var.project_name}-${var.stage}"
  action_group_name = "${var.project_name}-${var.stage}-action-group"
  
  common_tags = {
    Project     = var.project_name
    Environment = var.stage
    ManagedBy   = "Terraform"
  }
}

# ==============================
# Log Analytics Workspace
# ==============================

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.name}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  
  tags = local.common_tags
}

# ==============================
# Action Group for Alerts
# ==============================

resource "azurerm_monitor_action_group" "main" {
  name                = local.action_group_name
  resource_group_name = var.resource_group_name
  short_name          = "ragalerts"
  
  email_receiver {
    name                    = "admin"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
  
  tags = local.common_tags
}

# ==============================
# Application Insights Alerts
# ==============================

resource "azurerm_monitor_metric_alert" "document_processor_errors" {
  name                = "${local.name}-document-processor-errors"
  resource_group_name = var.resource_group_name
  scopes              = [var.document_processor_function_id]
  description         = "Alert when document processor function has errors"
  
  severity    = 2
  frequency   = "PT5M"
  window_size = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "FunctionExecutionCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 3
    
    dimension {
      name     = "Status"
      operator = "Include"
      values   = ["Error"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  tags = local.common_tags
}

resource "azurerm_monitor_metric_alert" "query_processor_errors" {
  name                = "${local.name}-query-processor-errors"
  resource_group_name = var.resource_group_name
  scopes              = [var.query_processor_function_id]
  description         = "Alert when query processor function has errors"
  
  severity    = 2
  frequency   = "PT5M"
  window_size = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "FunctionExecutionCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 3
    
    dimension {
      name     = "Status"
      operator = "Include"
      values   = ["Error"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  tags = local.common_tags
}

resource "azurerm_monitor_metric_alert" "upload_handler_errors" {
  name                = "${local.name}-upload-handler-errors"
  resource_group_name = var.resource_group_name
  scopes              = [var.upload_handler_function_id]
  description         = "Alert when upload handler function has errors"
  
  severity    = 2
  frequency   = "PT5M"
  window_size = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "FunctionExecutionCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 3
    
    dimension {
      name     = "Status"
      operator = "Include"
      values   = ["Error"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  tags = local.common_tags
}

# ==============================
# Azure Monitor Dashboard
# ==============================

resource "azurerm_portal_dashboard" "main" {
  name                = "${local.name}-dashboard"
  resource_group_name = var.resource_group_name
  location            = var.location
  dashboard_properties = jsonencode({
    "lenses": {
      "0": {
        "order": 0,
        "parts": {
          "0": {
            "position": {
              "x": 0,
              "y": 0,
              "colSpan": 6,
              "rowSpan": 4
            },
            "metadata": {
              "inputs": [
                {
                  "name": "resourceTypeMode",
                  "value": "workspace"
                },
                {
                  "name": "TimeRange",
                  "value": "P1D"
                },
                {
                  "name": "Dimensions",
                  "value": {
                    "xAxis": {
                      "name": "TimeGenerated",
                      "type": "datetime"
                    },
                    "yAxis": [
                      {
                        "name": "CountValue",
                        "type": "long"
                      }
                    ],
                    "splitBy": [
                      {
                        "name": "Level",
                        "type": "string"
                      }
                    ],
                    "aggregation": "Sum"
                  }
                },
                {
                  "name": "Query",
                  "value": "AppTraces\n| where AppRoleName contains \"${var.project_name}\"\n| summarize CountValue = count() by bin(TimeGenerated, 5m), Level\n| render timechart"
                },
                {
                  "name": "WorkspaceId",
                  "value": "${azurerm_log_analytics_workspace.main.id}"
                }
              ],
              "type": "Extension/AppInsightsExtension/PartType/AnalyticsLineChartPart",
              "settings": {
                "content": {
                  "title": "Function Logs by Level",
                  "subtitle": "Last 24 hours"
                }
              }
            }
          },
          "1": {
            "position": {
              "x": 6,
              "y": 0,
              "colSpan": 6,
              "rowSpan": 4
            },
            "metadata": {
              "inputs": [
                {
                  "name": "resourceTypeMode",
                  "value": "workspace"
                },
                {
                  "name": "TimeRange",
                  "value": "P1D"
                },
                {
                  "name": "Dimensions",
                  "value": {
                    "xAxis": {
                      "name": "TimeGenerated",
                      "type": "datetime"
                    },
                    "yAxis": [
                      {
                        "name": "CountValue",
                        "type": "long"
                      }
                    ],
                    "splitBy": [
                      {
                        "name": "AppRoleName",
                        "type": "string"
                      }
                    ],
                    "aggregation": "Sum"
                  }
                },
                {
                  "name": "Query",
                  "value": "AppRequests\n| where AppRoleName contains \"${var.project_name}\"\n| summarize CountValue = count() by bin(TimeGenerated, 5m), AppRoleName\n| render timechart"
                },
                {
                  "name": "WorkspaceId",
                  "value": "${azurerm_log_analytics_workspace.main.id}"
                }
              ],
              "type": "Extension/AppInsightsExtension/PartType/AnalyticsLineChartPart",
              "settings": {
                "content": {
                  "title": "Function Requests",
                  "subtitle": "Last 24 hours"
                }
              }
            }
          }
        }
      }
    }
  })
  
  tags = local.common_tags
}
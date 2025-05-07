# modules/compute/main.tf

# ===============================
# Compute Module for RAG System
# ===============================

# =========================
# Locals
# =========================

locals {
  name                    = "${var.project_name}-${var.stage}" 
  document_processor_name = "${var.project_name}-${var.stage}-document-processor"
  query_processor_name    = "${var.project_name}-${var.stage}-query-processor"
  upload_handler_name     = "${var.project_name}-${var.stage}-upload-handler"
  db_init_name            = "${var.project_name}-${var.stage}-db-init"
  auth_handler_name       = "${var.project_name}-${var.stage}-auth-handler"
  
  common_tags = {
    Project     = var.project_name
    Environment = var.stage
    ManagedBy   = "Terraform"
  }
}

# ===================================================================
# Store GEMINI_API_KEY credentials placeholder in Azure Key Vault
# ===================================================================

resource "azurerm_key_vault_secret" "gemini_api_credentials" {
  name         = "gemini-api-key"
  value        = jsonencode({
    GEMINI_API_KEY = var.gemini_api_key
  })
  key_vault_id = var.key_vault_id
}

# ==========================
# Function App Service Plan
# ==========================

resource "azurerm_service_plan" "function" {
  name                = "${local.name}-function-plan"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "EP1" # Premium tier for VNet integration

  tags = local.common_tags
}

# ==========================
# Storage for Function Apps
# ==========================

resource "azurerm_storage_account" "function" {
  name                     = "${var.project_name}${var.stage}func"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"

  tags = local.common_tags
}

# ==========================
# Function Apps
# ==========================

resource "azurerm_linux_function_app" "document_processor" {
  name                       = local.document_processor_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  service_plan_id            = azurerm_service_plan.function.id
  storage_account_name       = azurerm_storage_account.function.name
  storage_account_access_key = azurerm_storage_account.function.primary_access_key
  
  site_config {
    application_stack {
      python_version = "3.11"
    }
    
    application_insights_connection_string = azurerm_application_insights.function.connection_string
    application_insights_key               = azurerm_application_insights.function.instrumentation_key
    
    vnet_route_all_enabled = true
    
    cors {
      allowed_origins = ["*"] # Adjust for your environment
    }
  }
  
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"    = "python"
    "AzureWebJobsDisableHomepage" = "true"
    "DOCUMENTS_CONTAINER"         = var.documents_container
    "DOCUMENTS_STORAGE"           = var.documents_storage_account
    "METADATA_COSMOS_ACCOUNT"     = var.metadata_cosmos_account
    "METADATA_COSMOS_DATABASE"    = var.metadata_cosmos_database
    "METADATA_CONTAINER"          = var.metadata_cosmos_container
    "STAGE"                       = var.stage
    "DB_SECRET_URI"               = var.db_secret_uri
    "GEMINI_SECRET_URI"           = "https://${var.key_vault_name}.vault.azure.net/secrets/gemini-api-key"
    "GEMINI_MODEL"                = var.gemini_model
    "GEMINI_EMBEDDING_MODEL"      = var.gemini_embedding_model
    "TEMPERATURE"                 = "0.2"
    "MAX_OUTPUT_TOKENS"           = "1024"
    "TOP_K"                       = "40"
    "TOP_P"                       = "0.8"
    "SIMILARITY_THRESHOLD"        = "0.7"
  }
  
  identity {
    type = "SystemAssigned"
  }
  
  virtual_network_subnet_id = var.subnet_id

  tags = {
    Name = local.document_processor_name
  }
}

resource "azurerm_linux_function_app" "query_processor" {
  name                       = local.query_processor_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  service_plan_id            = azurerm_service_plan.function.id
  storage_account_name       = azurerm_storage_account.function.name
  storage_account_access_key = azurerm_storage_account.function.primary_access_key
  
  site_config {
    application_stack {
      python_version = "3.11"
    }
    
    application_insights_connection_string = azurerm_application_insights.function.connection_string
    application_insights_key               = azurerm_application_insights.function.instrumentation_key
    
    vnet_route_all_enabled = true
    
    cors {
      allowed_origins = ["*"] # Adjust for your environment
    }
  }
  
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"    = "python"
    "AzureWebJobsDisableHomepage" = "true"
    "DOCUMENTS_CONTAINER"         = var.documents_container
    "DOCUMENTS_STORAGE"           = var.documents_storage_account
    "METADATA_COSMOS_ACCOUNT"     = var.metadata_cosmos_account
    "METADATA_COSMOS_DATABASE"    = var.metadata_cosmos_database
    "METADATA_CONTAINER"          = var.metadata_cosmos_container
    "STAGE"                       = var.stage
    "DB_SECRET_URI"               = var.db_secret_uri
    "GEMINI_SECRET_URI"           = "https://${var.key_vault_name}.vault.azure.net/secrets/gemini-api-key"
    "GEMINI_MODEL"                = var.gemini_model
    "GEMINI_EMBEDDING_MODEL"      = var.gemini_embedding_model
    "TEMPERATURE"                 = "0.2"
    "MAX_OUTPUT_TOKENS"           = "1024"
    "TOP_K"                       = "40"
    "TOP_P"                       = "0.8"
    "SIMILARITY_THRESHOLD"        = "0.7"
  }
  
  identity {
    type = "SystemAssigned"
  }
  
  virtual_network_subnet_id = var.subnet_id

  tags = {
    Name = local.query_processor_name
  }
}

resource "azurerm_linux_function_app" "upload_handler" {
  name                       = local.upload_handler_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  service_plan_id            = azurerm_service_plan.function.id
  storage_account_name       = azurerm_storage_account.function.name
  storage_account_access_key = azurerm_storage_account.function.primary_access_key
  
  site_config {
    application_stack {
      python_version = "3.11"
    }
    
    application_insights_connection_string = azurerm_application_insights.function.connection_string
    application_insights_key               = azurerm_application_insights.function.instrumentation_key
    
    vnet_route_all_enabled = true
    
    cors {
      allowed_origins = ["*"] # Adjust for your environment
    }
  }
  
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"    = "python"
    "AzureWebJobsDisableHomepage" = "true"
    "DOCUMENTS_CONTAINER"         = var.documents_container
    "DOCUMENTS_STORAGE"           = var.documents_storage_account
    "METADATA_COSMOS_ACCOUNT"     = var.metadata_cosmos_account
    "METADATA_COSMOS_DATABASE"    = var.metadata_cosmos_database
    "METADATA_CONTAINER"          = var.metadata_cosmos_container
    "STAGE"                       = var.stage
    "DB_SECRET_URI"               = var.db_secret_uri
  }
  
  identity {
    type = "SystemAssigned"
  }
  
  virtual_network_subnet_id = var.subnet_id

  tags = {
    Name = local.upload_handler_name
  }
}

resource "azurerm_linux_function_app" "db_init" {
  name                       = local.db_init_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  service_plan_id            = azurerm_service_plan.function.id
  storage_account_name       = azurerm_storage_account.function.name
  storage_account_access_key = azurerm_storage_account.function.primary_access_key
  
  site_config {
    application_stack {
      python_version = "3.11"
    }
    
    application_insights_connection_string = azurerm_application_insights.function.connection_string
    application_insights_key               = azurerm_application_insights.function.instrumentation_key
    
    vnet_route_all_enabled = true
    
    cors {
      allowed_origins = ["*"] # Adjust for your environment
    }
  }
  
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"    = "python"
    "AzureWebJobsDisableHomepage" = "true"
    "DOCUMENTS_CONTAINER"         = var.documents_container
    "DOCUMENTS_STORAGE"           = var.documents_storage_account
    "METADATA_COSMOS_ACCOUNT"     = var.metadata_cosmos_account
    "METADATA_COSMOS_DATABASE"    = var.metadata_cosmos_database
    "METADATA_CONTAINER"          = var.metadata_cosmos_container
    "STAGE"                       = var.stage
    "DB_SECRET_URI"               = var.db_secret_uri
    "MAX_RETRIES"                 = var.max_retries
    "RETRY_DELAY"                 = var.retry_delay
  }
  
  identity {
    type = "SystemAssigned"
  }
  
  virtual_network_subnet_id = var.subnet_id

  tags = {
    Name = local.db_init_name
  }
}

resource "azurerm_linux_function_app" "auth_handler" {
  name                       = local.auth_handler_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  service_plan_id            = azurerm_service_plan.function.id
  storage_account_name       = azurerm_storage_account.function.name
  storage_account_access_key = azurerm_storage_account.function.primary_access_key
  
  site_config {
    application_stack {
      python_version = "3.11"
    }
    
    application_insights_connection_string = azurerm_application_insights.function.connection_string
    application_insights_key               = azurerm_application_insights.function.instrumentation_key
    
    vnet_route_all_enabled = true
    
    cors {
      allowed_origins = ["*"] # Adjust for your environment
    }
  }
  
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"    = "python"
    "AzureWebJobsDisableHomepage" = "true"
    "STAGE"                       = var.stage
    "AAD_B2C_TENANT_ID"           = var.aad_b2c_tenant_id
    "AAD_B2C_APPLICATION_ID"      = var.aad_b2c_application_id
  }
  
  identity {
    type = "SystemAssigned"
  }
  
  virtual_network_subnet_id = var.subnet_id

  tags = {
    Name = local.auth_handler_name
  }
}

# ===================================================================
# Key Vault Access Policies for Function Apps
# ===================================================================

resource "azurerm_key_vault_access_policy" "document_processor" {
  key_vault_id = var.key_vault_id
  tenant_id    = azurerm_linux_function_app.document_processor.identity[0].tenant_id
  object_id    = azurerm_linux_function_app.document_processor.identity[0].principal_id
  
  secret_permissions = [
    "Get", "List"
  ]
}

resource "azurerm_key_vault_access_policy" "query_processor" {
  key_vault_id = var.key_vault_id
  tenant_id    = azurerm_linux_function_app.query_processor.identity[0].tenant_id
  object_id    = azurerm_linux_function_app.query_processor.identity[0].principal_id
  
  secret_permissions = [
    "Get", "List"
  ]
}

resource "azurerm_key_vault_access_policy" "upload_handler" {
  key_vault_id = var.key_vault_id
  tenant_id    = azurerm_linux_function_app.upload_handler.identity[0].tenant_id
  object_id    = azurerm_linux_function_app.upload_handler.identity[0].principal_id
  
  secret_permissions = [
    "Get", "List"
  ]
}

resource "azurerm_key_vault_access_policy" "db_init" {
  key_vault_id = var.key_vault_id
  tenant_id    = azurerm_linux_function_app.db_init.identity[0].tenant_id
  object_id    = azurerm_linux_function_app.db_init.identity[0].principal_id
  
  secret_permissions = [
    "Get", "List"
  ]
}

# ==========================
# Application Insights
# ==========================

resource "azurerm_log_analytics_workspace" "function" {
  name                = "${local.name}-log-analytics"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = local.common_tags
}

resource "azurerm_application_insights" "function" {
  name                = "${local.name}-app-insights"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.function.id
  application_type    = "web"

  tags = local.common_tags
}

# ==========================
# Function Keys
# ==========================

# Note: In Azure, function keys are auto-generated and usually retrieved via REST API
# This is a placeholder for the output - in real deployment, you'd use Azure CLI or Rest API
resource "null_resource" "function_keys" {
  triggers = {
    document_processor_id = azurerm_linux_function_app.document_processor.id
    query_processor_id    = azurerm_linux_function_app.query_processor.id
    upload_handler_id     = azurerm_linux_function_app.upload_handler.id
    db_init_id            = azurerm_linux_function_app.db_init.id
    auth_handler_id       = azurerm_linux_function_app.auth_handler.id
  }
  
  # In actual implementation, you might use a provisioner to get keys
  # Or use data sources if available
}
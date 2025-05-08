# ============================================================
# Root Module for RAG Application Deployment in Dev env (main.tf)
# ============================================================
# Provisions project-wide infrastructure by composing all modules

# =====================================
# Resource Group for all resources
# =====================================

resource "azurerm_resource_group" "main" {
  name     = "${var.project_name}-${var.stage}-rg"
  location = var.location
  
  tags = {
    Environment = var.stage
    Project     = var.project_name
  }
}

# =====================================
# Storage Account for Function App Code
# =====================================

resource "azurerm_storage_account" "function_code" {
  name                     = "${var.project_name}${var.stage}funcs"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  
  tags = {
    Environment = var.stage
    Project     = var.project_name
  }
  
  # Prevent destruction of existing storage accounts
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "function_code" {
  name                  = "functions"
  storage_account_name  = azurerm_storage_account.function_code.name
  container_access_type = "private"
}

# ====================
# Network Module
# ====================

module "network" {
  source = "../../modules/network"
  
  project_name = var.project_name
  stage        = var.stage
  location     = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space = var.address_space
  subnet_prefixes = var.subnet_prefixes
  
  # Cost optimization - use single NAT gateway for non-prod environments
  single_nat_gateway = var.single_nat_gateway
  
  # Enable flow logs only in production for better monitoring
  enable_flow_logs = var.enable_flow_logs
  
  # Create bastion in dev environment
  create_bastion = var.create_bastion
  bastion_allowed_cidr = var.bastion_allowed_cidr
  
  depends_on = [azurerm_resource_group.main]
}

# =======================
# Storage (Blob + Cosmos DB)
# =======================

module "storage" {
  source = "../../modules/storage"
  
  project_name = var.project_name
  stage        = var.stage
  location     = var.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Optional storage lifecycle rules
  enable_lifecycle_rules     = var.enable_lifecycle_rules
  standard_ia_transition_days = var.standard_ia_transition_days
  archive_transition_days    = var.archive_transition_days
  
  depends_on = [azurerm_resource_group.main]
}

# =====================
# Database (PostgreSQL)
# =====================

module "database" {
  source = "../../modules/database"
  
  project_name       = var.project_name
  stage              = var.stage
  location           = var.location
  resource_group_name = azurerm_resource_group.main.name
  vnet_id             = module.network.vnet_id
  subnet_id           = module.network.database_subnet_id
  admin_username      = var.db_username
  db_name             = var.db_name
  db_sku_name         = var.db_sku_name
  db_storage_mb       = var.db_storage_mb
  
  # Password reset option
  reset_db_password   = var.reset_db_password
  
  depends_on = [module.network]
}

# Add auth module before api and compute modules
module "auth" {
  source = "../../modules/auth"
  
  project_name        = var.project_name
  stage               = var.stage
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  
  depends_on = [azurerm_resource_group.main]
}

# =======================
# Compute (Function Apps)
# =======================

module "compute" {
  source = "../../modules/compute"
  
  project_name       = var.project_name
  stage              = var.stage
  location           = var.location
  resource_group_name = azurerm_resource_group.main.name
  function_memory_size = var.function_memory_size
  function_timeout    = var.function_timeout
  
  # Pass outputs from storage module
  documents_container = module.storage.documents_container_name
  documents_storage_account = module.storage.documents_storage_account_name
  metadata_cosmos_account = module.storage.metadata_cosmos_account_name
  metadata_cosmos_database = module.storage.metadata_cosmos_database_name
  metadata_cosmos_container = module.storage.metadata_container_name
  function_storage_account = azurerm_storage_account.function_code.name
  
  # Pass VPC configuration
  vnet_id                 = module.network.vnet_id
  subnet_id               = module.network.function_subnet_id
  
  # Pass Key Vault info
  key_vault_id           = module.database.key_vault_id
  key_vault_name         = module.database.key_vault_name
  db_secret_uri          = module.database.db_secret_uri
  
  # Auth information
  aad_b2c_tenant_id      = module.auth.aad_b2c_tenant_id
  aad_b2c_application_id = module.auth.aad_b2c_application_id
  
  depends_on = [
    module.storage, 
    module.network, 
    module.database, 
    module.auth, 
    azurerm_storage_account.function_code
  ]
}

# ====================
# API Management Module
# ====================

module "api" {
  source = "../../modules/api"
  
  project_name            = var.project_name
  stage                   = var.stage
  location                = var.location
  resource_group_name     = azurerm_resource_group.main.name
  vnet_id                 = module.network.vnet_id
  subnet_id               = module.network.api_subnet_id
  
  document_processor_function_id = module.compute.document_processor_function_id
  query_processor_function_id = module.compute.query_processor_function_id
  upload_handler_function_id = module.compute.upload_handler_function_id
  
  document_processor_function_name = module.compute.document_processor_function_name
  query_processor_function_name = module.compute.query_processor_function_name
  upload_handler_function_name = module.compute.upload_handler_function_name
  auth_handler_function_name = module.compute.auth_handler_function_name
  
  document_processor_function_key = module.compute.document_processor_function_key
  query_processor_function_key = module.compute.query_processor_function_key
  upload_handler_function_key = module.compute.upload_handler_function_key
  auth_handler_function_key = module.compute.auth_handler_function_key
  
  auth_handler_function_id = module.compute.auth_handler_function_id
  
  # Auth references from auth module
  aad_b2c_tenant_id       = module.auth.aad_b2c_tenant_id
  aad_b2c_application_id  = module.auth.aad_b2c_application_id
  aad_b2c_policy_name     = module.auth.aad_b2c_policy_name
  
  # Make sure compute module is created first
  depends_on = [module.compute, module.auth]
}

# ===================
# Monitoring & Alerts
# ===================

module "monitoring" {
  source = "../../modules/monitoring"
  
  project_name              = var.project_name
  stage                     = var.stage
  location                  = var.location
  resource_group_name       = azurerm_resource_group.main.name
  alert_email               = var.alert_email
  document_processor_function_id = module.compute.document_processor_function_id
  query_processor_function_id = module.compute.query_processor_function_id
  upload_handler_function_id = module.compute.upload_handler_function_id
  auth_handler_function_id = module.compute.auth_handler_function_id
  
  depends_on = [module.compute]
}

# ===================
# Outputs
# ===================

output "api_endpoint" {
  description = "URL of the API endpoint"
  value       = module.api.api_endpoint
}

output "document_storage_account" {
  description = "Name of the document storage account"
  value       = module.storage.documents_storage_account_name
}

output "document_container" {
  description = "Name of the document container"
  value       = module.storage.documents_container_name 
}

output "metadata_cosmos_account" {
  description = "Name of the Cosmos DB metadata account"
  value       = module.storage.metadata_cosmos_account_name
}

output "metadata_container" {
  description = "Name of the metadata container in Cosmos DB"
  value       = module.storage.metadata_container_name
}

output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = module.network.vnet_id
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = module.database.key_vault_name
}

output "b2c_tenant_id" {
  description = "ID of the Azure AD B2C Tenant"
  value       = module.auth.aad_b2c_tenant_id
}

output "b2c_application_id" {
  description = "ID of the Azure AD B2C Application"
  value       = module.auth.aad_b2c_application_id
}

output "auth_endpoint" {
  description = "URL of the auth endpoint"
  value       = "${module.api.api_endpoint}/auth"
}
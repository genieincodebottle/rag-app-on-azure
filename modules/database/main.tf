# modules/database/main.tf

# ================================
# Database Module for RAG System
# ================================
# Sets up PostgreSQL Flexible Server with Key Vault integration

locals {
  name = "${var.project_name}-${var.stage}"
  server_name = "${var.project_name}-${var.stage}-postgres"
  key_vault_name = "${var.project_name}-${var.stage}-kv"
  
  # Define fallback values for DB endpoints and connection info
  db_endpoint_fallback = "${local.server_name}.postgres.database.azure.com"
  db_port_fallback = 5432
  
  common_tags = {
    Project     = var.project_name
    Environment = var.stage
    ManagedBy   = "Terraform"
  }
}

# Generate a random password for the database
resource "random_password" "postgres_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  
  # Only regenerate password when explicitly told to
  lifecycle {
    ignore_changes = all
  }
}

# Create a DNS zone for private PostgreSQL server
resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${local.name}-postgres-vnet-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = var.vnet_id
  registration_enabled   = false
}

# Create PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = local.server_name
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = "14"
  delegated_subnet_id    = var.subnet_id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id
  administrator_login    = var.admin_username
  administrator_password = random_password.postgres_password.result
  storage_mb             = var.db_storage_mb
  sku_name               = var.db_sku_name
  backup_retention_days  = 7
  zone                   = "1"
  
  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.postgres
  ]
  
  tags = local.common_tags
  
  # Handle existing instances
  lifecycle {
    prevent_destroy = true
    # Prevent password changes after creation unless reset is requested
    ignore_changes = [administrator_password]
  }
}

# Create database
resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = var.db_name
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Configure PostgreSQL server parameters
resource "azurerm_postgresql_flexible_server_configuration" "shared_buffers" {
  name      = "shared_buffers"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "128MB"
}

# Create Key Vault
resource "azurerm_key_vault" "main" {
  name                        = local.key_vault_name
  location                    = var.location
  resource_group_name         = var.resource_group_name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"
  
  tags = local.common_tags
}

# Get current Azure account configuration
data "azurerm_client_config" "current" {}

# Configure Key Vault access policy for the currently authenticated user (for Terraform)
resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"
  ]
}

# Store the database credentials in Azure Key Vault
resource "azurerm_key_vault_secret" "db_credentials" {
  name         = "db-credentials"
  value = jsonencode({
    username = var.admin_username
    password = random_password.postgres_password.result
    host     = azurerm_postgresql_flexible_server.main.fqdn
    port     = 5432
    dbname   = var.db_name
  })
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [
    azurerm_key_vault_access_policy.terraform,
    azurerm_postgresql_flexible_server_database.main
  ]
}
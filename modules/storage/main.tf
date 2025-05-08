# modules/storage/main.tf

# ================================================
# Storage Module for RAG System (Blob + Cosmos DB)
# ================================================
# Provisions secure document storage and metadata store with best practices

# ==============================
# Locals
# ==============================

locals {
  documents_storage_name = "${var.project_name}${var.stage}docs"
  metadata_cosmos_name = "${var.project_name}${var.stage}metadata"
  documents_container_name = "documents"
  metadata_container_name = "metadata"

  common_tags = {
    Project     = var.project_name
    Environment = var.stage
    ManagedBy   = "Terraform"
  }
}

# ==============================
# Document Storage - Blob Storage
# ==============================

resource "azurerm_storage_account" "documents" {
  name                     = local.documents_storage_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  
  tags = {
    Name = local.documents_storage_name
    Environment = var.stage
  }
  
  # Prevent destruction of existing storage accounts
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "documents" {
  name                  = local.documents_container_name
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

# Azure Blob Storage lifecycle management policy
resource "azurerm_storage_management_policy" "documents" {
  count              = var.enable_lifecycle_rules ? 1 : 0
  storage_account_id = azurerm_storage_account.documents.id

  rule {
    name    = "archive-old-documents"
    enabled = true
    filters {
      prefix_match = ["${local.documents_container_name}/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = var.standard_ia_transition_days
        tier_to_archive_after_days_since_modification_greater_than = var.archive_transition_days
      }
    }
  }
}

# ==============================
# Cosmos DB for metadata storage
# ==============================

resource "azurerm_cosmosdb_account" "metadata" {
  name                = local.metadata_cosmos_name
  location            = var.location
  resource_group_name = var.resource_group_name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  
  consistency_policy {
    consistency_level       = "Session"
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }
  
  geo_location {
    location          = var.location
    failover_priority = 0
  }
  
  capabilities {
    name = "EnableServerless"
  }
  
  tags = {
    Name = local.metadata_cosmos_name
    Environment = var.stage
  }
  
  # Prevent destruction of existing accounts
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_cosmosdb_sql_database" "metadata" {
  name                = "ragapp"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.metadata.name
}

resource "azurerm_cosmosdb_sql_container" "metadata" {
  name                = local.metadata_container_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.metadata.name
  database_name       = azurerm_cosmosdb_sql_database.metadata.name
  
  partition_key {
    paths = ["/id"]
  }
  
  # Configure indexing policy for efficient queries
  indexing_policy {
    indexing_mode = "consistent"
    
    included_path {
      path = "/*"
    }
    
    excluded_path {
      path = "/\"_etag\"/?"
    }
  }
  
  # Add a unique key for document IDs
  unique_key {
    paths = ["/document_id"]
  }
}
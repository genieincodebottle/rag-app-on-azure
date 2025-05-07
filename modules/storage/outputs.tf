# modules/storage/outputs.tf

output "documents_storage_account_name" {
  description = "Name of the document storage account"
  value       = azurerm_storage_account.documents.name
}

output "documents_storage_account_id" {
  description = "ID of the document storage account"
  value       = azurerm_storage_account.documents.id
}

output "documents_container_name" {
  description = "Name of the document container"
  value       = azurerm_storage_container.documents.name
}

output "metadata_cosmos_account_name" {
  description = "Name of the Cosmos DB metadata account"
  value       = azurerm_cosmosdb_account.metadata.name
}

output "metadata_cosmos_account_id" {
  description = "ID of the Cosmos DB metadata account"
  value       = azurerm_cosmosdb_account.metadata.id
}

output "metadata_cosmos_endpoint" {
  description = "Endpoint of the Cosmos DB metadata account"
  value       = azurerm_cosmosdb_account.metadata.endpoint
}

output "metadata_cosmos_database_name" {
  description = "Name of the Cosmos DB metadata database"
  value       = azurerm_cosmosdb_sql_database.metadata.name
}

output "metadata_container_name" {
  description = "Name of the metadata container in Cosmos DB"
  value       = azurerm_cosmosdb_sql_container.metadata.name
}
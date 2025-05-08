output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.main.name
}
output "key_vault_id" {
  value = azurerm_key_vault.main.id
}

output "db_secret_uri" {
  value = azurerm_key_vault_secret.db_credentials.id
}
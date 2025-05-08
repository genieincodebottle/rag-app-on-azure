output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.main.name
}
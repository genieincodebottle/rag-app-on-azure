output "document_processor_function_id" {
  value = azurerm_linux_function_app.document_processor.id
}

output "document_processor_function_name" {
  value = azurerm_linux_function_app.document_processor.name
}

output "query_processor_function_id" {
  value = azurerm_linux_function_app.query_processor.id
}

output "query_processor_function_name" {
  value = azurerm_linux_function_app.query_processor.name
}

output "upload_handler_function_id" {
  value = azurerm_linux_function_app.upload_handler.id
}

output "upload_handler_function_name" {
  value = azurerm_linux_function_app.upload_handler.name
}

output "auth_handler_function_id" {
  value = azurerm_linux_function_app.auth_handler.id
}

output "auth_handler_function_name" {
  value = azurerm_linux_function_app.auth_handler.name
}

output "db_init_function_id" {
  value = azurerm_linux_function_app.db_init.id
}

output "db_init_function_name" {
  value = azurerm_linux_function_app.db_init.name
}

# Placeholder keys - replace with actual logic when needed
output "document_processor_function_key" {
  value = "dummy-key-document-processor"
}

output "query_processor_function_key" {
  value = "dummy-key-query-processor"
}

output "upload_handler_function_key" {
  value = "dummy-key-upload-handler"
}

output "auth_handler_function_key" {
  value = "dummy-key-auth-handler"
}

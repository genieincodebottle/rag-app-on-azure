# modules/network/outputs.tf

# =========================
# Network Module Outputs
# =========================

output "vnet_id" {
  description = "The ID of the Virtual Network"
  value       = azurerm_virtual_network.main.id
}

output "function_subnet_id" {
  description = "ID of the function subnet"
  value       = azurerm_subnet.function.id
}

output "database_subnet_id" {
  description = "ID of the database subnet"
  value       = azurerm_subnet.database.id
}

output "api_subnet_id" {
  description = "ID of the API subnet"
  value       = azurerm_subnet.api.id
}

output "bastion_subnet_id" {
  description = "ID of the bastion subnet"
  value       = var.create_bastion ? azurerm_subnet.bastion[0].id : ""
}

output "function_nsg_id" {
  description = "ID of the function network security group"
  value       = azurerm_network_security_group.function.id
}

output "database_nsg_id" {
  description = "ID of the database network security group"
  value       = azurerm_network_security_group.database.id
}

output "api_nsg_id" {
  description = "ID of the API network security group"
  value       = azurerm_network_security_group.api.id
}

output "nat_gateway_ips" {
  description = "Public IP addresses of NAT Gateways"
  value       = azurerm_public_ip.nat[*].ip_address
}

output "address_space" {
  description = "CIDR block of the Virtual Network"
  value       = var.address_space
}
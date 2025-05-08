# modules/database/variables.tf

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "stage" {
  description = "Deployment stage (dev, staging, prod)"
  type        = string
}

variable "location" {
  description = "Azure location"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "vnet_id" {
  description = "ID of the Virtual Network"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet for the database"
  type        = string
}

variable "admin_username" {
  description = "Admin username for the PostgreSQL server"
  type        = string
  default     = "pgadmin"
}

variable "db_name" {
  description = "Name of the database"
  type        = string
  default     = "ragapp"
}

variable "db_server_name" {
  description = "Name of the database server"
  type        = string
}

variable "db_sku_name" {
  description = "SKU name for the PostgreSQL Flexible Server"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "db_storage_mb" {
  description = "Storage for the PostgreSQL server in MB"
  type        = number
  default     = 5120 # 5GB
}

variable "reset_db_password" {
  description = "Flag to reset the database password"
  type        = bool
  default     = false
}

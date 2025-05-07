# modules/compute/variables.tf

# =========================
# Compute Module Variables
# =========================

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

# -------------------------
# Function Configuration
# -------------------------
variable "function_memory_size" {
  description = "Memory size for Function apps in MB"
  type        = number
  default     = 1536
}

variable "function_timeout" {
  description = "Timeout for Function apps in seconds"
  type        = number
  default     = 120
}

# -------------------------
# Storage & Metadata
# -------------------------
variable "documents_container" {
  description = "Name of the blob container for documents"
  type        = string
}

variable "documents_storage_account" {
  description = "Name of the storage account for documents"
  type        = string
}

variable "metadata_cosmos_account" {
  description = "Name of the Cosmos DB account for metadata"
  type        = string
}

variable "metadata_cosmos_database" {
  description = "Name of the Cosmos DB database for metadata"
  type        = string
}

variable "metadata_cosmos_container" {
  description = "Name of the Cosmos DB container for metadata"
  type        = string
}

variable "function_storage_account" {
  description = "Name of the storage account for function code"
  type        = string
}

# -------------------------
# Networking
# -------------------------
variable "vnet_id" {
  description = "ID of the Virtual Network"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet for functions"
  type        = string
}

# -------------------------
# Key Vault
# -------------------------
variable "key_vault_id" {
  description = "ID of the Key Vault"
  type        = string
}

variable "key_vault_name" {
  description = "Name of the Key Vault"
  type        = string
  default     = ""
}

variable "db_secret_uri" {
  description = "URI of the DB credentials secret in Key Vault"
  type        = string
}

# -------------------------
# Gemini Configuration
# -------------------------
variable "gemini_model" {
  description = "Gemini AI model to use"
  type        = string
  default     = "gemini-2.0-pro-exp-02-05"
}

variable "gemini_embedding_model" {
  description = "Gemini Embedding model to use"
  type        = string
  default     = "text-embedding-004"
}

variable "gemini_api_key" {
  description = "Google's Gemini API Key"
  type        = string
  default     = "PLACE_HOLDER"
  sensitive   = true
}

variable "max_retries" {
  description = "Max Retry"
  type        = number
  default     = 5
}

variable "retry_delay" {
  description = "Retry Delay"
  type        = number
  default     = 10
}

# -------------------------
# Auth Configuration
# -------------------------
variable "aad_b2c_tenant_id" {
  description = "Azure AD B2C Tenant ID"
  type        = string
  default     = ""
}

variable "aad_b2c_application_id" {
  description = "Azure AD B2C Application ID"
  type        = string
  default     = ""
}
# =========================
# Root variables.tf
# =========================

# -------------------------
# Project Configuration
# -------------------------
variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "stage" {
  description = "Deployment stage (dev, staging, prod)"
  type        = string
  default     = "dev"
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
# Network Configuration
# -------------------------
variable "address_space" {
  description = "CIDR block for the Virtual Network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_prefixes" {
  description = "Subnet address prefixes"
  type        = map(string)
  default = {
    function = "10.0.0.0/24"
    database = "10.0.1.0/24"
    api      = "10.0.2.0/24"
    bastion  = "10.0.3.0/24"
  }
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway instead of one per AZ (cost saving for dev)"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable Network Flow Logs for monitoring"
  type        = bool
  default     = false
}

variable "create_bastion" {
  description = "Create an Azure Bastion service"
  type        = bool
  default     = true
}

variable "bastion_allowed_cidr" {
  description = "CIDR blocks allowed to connect to bastion hosts"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Should be restricted to your company IP range in production
}

# -------------------------
# Database Configuration
# -------------------------
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

variable "db_name" {
  description = "Name of the database"
  type        = string
  default     = "ragapp"
}

variable "db_username" {
  description = "Username for the database"
  type        = string
  default     = "ragadmin"
}

variable "reset_db_password" {
  description = "Flag to reset the database password"
  type        = bool
  default     = false
}

# -------------------------
# Storage Configuration
# -------------------------
variable "enable_lifecycle_rules" {
  description = "Enable Storage lifecycle rules for cost optimization"
  type        = bool
  default     = true
}

variable "standard_ia_transition_days" {
  description = "Days before transitioning to Cool storage tier"
  type        = number
  default     = 90
}

variable "archive_transition_days" {
  description = "Days before transitioning to Archive storage tier"
  type        = number
  default     = 365
}

# -------------------------
# Monitoring Configuration
# -------------------------
variable "alert_email" {
  description = "Email address for monitoring alerts"
  type        = string
  default     = ""  # Set this in your tfvars file
}

# -------------------------
# Dashboard References
# -------------------------
variable "metadata_container_name" {
  description = "Name of the Cosmos DB container for metadata (used in prod dashboards)"
  type        = string
  default     = ""
}

variable "documents_container_name" {
  description = "Name of the Storage container for documents (used in prod dashboards)"
  type        = string
  default     = ""
}

# -------------------------
# GitHub Repo
# -------------------------
variable "github_repo" {
  description = "GitHub Repo Name"
  type        = string
  default     = "genieincodebottle/rag-app-on-azure"
}

variable "github_branch" {
  description = "GitHub Branch"
  type        = string
  default     = "develop"
}
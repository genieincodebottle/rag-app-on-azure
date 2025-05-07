# modules/network/variables.tf

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

variable "address_space" {
  description = "CIDR block for the Virtual Network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_prefixes" {
  description = "Map of subnet names to address prefixes"
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
  default     = false
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs for network monitoring"
  type        = bool
  default     = false
}

variable "create_bastion" {
  description = "Create a bastion host"
  type        = bool
  default     = false
}

variable "bastion_allowed_cidr" {
  description = "CIDR blocks allowed to connect to bastion hosts"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
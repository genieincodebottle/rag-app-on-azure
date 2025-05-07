# modules/storage/variables.tf

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
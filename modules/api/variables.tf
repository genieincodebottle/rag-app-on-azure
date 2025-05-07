# modules/api/variables.tf

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
  description = "ID of the subnet for API Management"
  type        = string
}

# Function IDs and names
variable "document_processor_function_id" {
  description = "ID of the document processor Function app"
  type        = string
}

variable "query_processor_function_id" {
  description = "ID of the query processor Function app"
  type        = string
}

variable "upload_handler_function_id" {
  description = "ID of the upload handler Function app"
  type        = string
}

variable "auth_handler_function_id" {
  description = "ID of the auth handler Function app"
  type        = string
}

variable "document_processor_function_name" {
  description = "Name of the document processor Function app"
  type        = string
  default     = ""
}

variable "query_processor_function_name" {
  description = "Name of the query processor Function app"
  type        = string
  default     = ""
}

variable "upload_handler_function_name" {
  description = "Name of the upload handler Function app"
  type        = string
  default     = ""
}

variable "auth_handler_function_name" {
  description = "Name of the auth handler Function app"
  type        = string
  default     = ""
}

# Function keys
variable "document_processor_function_key" {
  description = "Function key for document processor"
  type        = string
  sensitive   = true
  default     = ""
}

variable "query_processor_function_key" {
  description = "Function key for query processor"
  type        = string
  sensitive   = true
  default     = ""
}

variable "upload_handler_function_key" {
  description = "Function key for upload handler"
  type        = string
  sensitive   = true
  default     = ""
}

variable "auth_handler_function_key" {
  description = "Function key for auth handler"
  type        = string
  sensitive   = true
  default     = ""
}

# Auth configuration
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

variable "aad_b2c_policy_name" {
  description = "Azure AD B2C Policy Name"
  type        = string
  default     = ""
}
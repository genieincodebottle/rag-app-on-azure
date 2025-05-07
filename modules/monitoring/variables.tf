# modules/monitoring/variables.tf

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

variable "alert_email" {
  description = "Email address for monitoring alerts"
  type        = string
}

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
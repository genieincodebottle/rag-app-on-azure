# modules/auth/outputs.tf

output "aad_b2c_tenant_id" {
  description = "ID of the Azure AD B2C tenant"
  value       = null_resource.b2c_tenant.triggers.tenant_id
}

output "aad_b2c_domain_name" {
  description = "Domain name of the Azure AD B2C tenant"
  value       = null_resource.b2c_tenant.triggers.domain_name
}

output "aad_b2c_application_id" {
  description = "ID of the Azure AD B2C application"
  value       = null_resource.b2c_application.triggers.application_id
}

output "aad_b2c_application_name" {
  description = "Name of the Azure AD B2C application"
  value       = null_resource.b2c_application.triggers.app_name
}

output "aad_b2c_policy_name" {
  description = "Name of the Azure AD B2C policy"
  value       = null_resource.b2c_policy.triggers.policy_name
}
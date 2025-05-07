# modules/auth/main.tf

# =========================
# Auth Module for RAG System
# =========================
# Sets up Azure AD B2C for user authentication

locals {
  name = "${var.project_name}-${var.stage}"
}

# Azure AD B2C resource (we mock this since Azure AD B2C cannot be fully automated with Terraform)
# In a real implementation, you would manually create the B2C tenant and use data sources
resource "azurerm_resource_group" "b2c" {
  name     = "${local.name}-b2c-rg"
  location = var.location
  
  tags = {
    Environment = var.stage
    Project     = var.project_name
  }
}

# Mock Azure AD B2C configuration - replace with real data sources in production
# These are placeholder values - the actual setup would use azuread provider
resource "null_resource" "b2c_tenant" {
  triggers = {
    # These would be actual outputs if using azuread provider
    tenant_id = "b2c-${local.name}-${var.location}-tenant-id"
    domain_name = "${local.name}.onmicrosoft.com"
  }
}

resource "null_resource" "b2c_application" {
  triggers = {
    application_id = "b2c-${local.name}-${var.location}-app-id" 
    app_name = "${local.name}-app"
  }
  
  depends_on = [null_resource.b2c_tenant]
}

resource "null_resource" "b2c_policy" {
  triggers = {
    policy_name = "B2C_1_SignUpSignIn"
  }
  
  depends_on = [null_resource.b2c_application]
}

# In a real implementation, you would configure redirect URIs, app settings, etc.
# For demonstration, we'll just output values that would be used by other modules
# modules/api/main.tf

# ================================
# API Management Module for RAG App
# ================================
# Defines API Management resources, APIs, operations, policies, CORS, and permissions

# ====================================
# Locals
# ====================================

locals {
  api_name = "${var.project_name}-${var.stage}-api"

  common_tags = {
    Project     = var.project_name
    Environment = var.stage
    ManagedBy   = "Terraform"
  }
}

# ====================================
# API Management Service
# ====================================

resource "azurerm_api_management" "main" {
  name                = local.api_name
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = "RAG App Team"
  publisher_email     = "admin@example.com"
  
  # Choose SKU based on environment
  sku_name = var.stage == "prod" ? "Premium_1" : "Developer_1"
  
  virtual_network_type = "Internal"
  virtual_network_configuration {
    subnet_id = var.subnet_id
  }
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
  
  # Prevent destruction of existing API Management
  lifecycle {
    prevent_destroy = true
  }
}

# ====================================
# Application Insights for API Gateway
# ====================================

resource "azurerm_application_insights" "api" {
  name                = "${local.api_name}-insights"
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = "web"
  
  tags = {
    Name = "${var.project_name}-${var.stage}-api-insights"
  }
}

resource "azurerm_api_management_logger" "main" {
  name                = "${local.api_name}-logger"
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  
  application_insights {
    instrumentation_key = azurerm_application_insights.api.instrumentation_key
  }
}

# ====================================
# API Management API
# ====================================

resource "azurerm_api_management_api" "main" {
  name                = "${var.project_name}-api"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.main.name
  revision            = "1"
  display_name        = "${var.project_name} API"
  path                = var.stage
  protocols           = ["https"]
  
  subscription_required = false
}

# ====================================
# JWT Validation Policy for API Management
# ====================================

resource "azurerm_api_management_api_policy" "jwt_validation" {
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  
  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <cors>
      <allowed-origins>
        <origin>*</origin>
      </allowed-origins>
      <allowed-methods>
        <method>GET</method>
        <method>POST</method>
        <method>OPTIONS</method>
      </allowed-methods>
      <allowed-headers>
        <header>Content-Type</header>
        <header>Authorization</header>
      </allowed-headers>
    </cors>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

# ====================================
# Auth operation
# ====================================

resource "azurerm_api_management_api_operation" "auth" {
  operation_id        = "auth"
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  display_name        = "Authentication"
  method              = "POST"
  url_template        = "/auth"
  description         = "Authentication operations"
  
  response {
    status_code = 200
  }
}

resource "azurerm_api_management_api_operation_policy" "auth" {
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  operation_id        = azurerm_api_management_api_operation.auth.operation_id
  
  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <cors>
      <allowed-origins>
        <origin>*</origin>
      </allowed-origins>
      <allowed-methods>
        <method>POST</method>
        <method>OPTIONS</method>
      </allowed-methods>
      <allowed-headers>
        <header>Content-Type</header>
        <header>Authorization</header>
      </allowed-headers>
    </cors>
    <set-backend-service id="apim-generated-policy" backend-id="auth-function" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

# ====================================
# Query operation
# ====================================

resource "azurerm_api_management_api_operation" "query" {
  operation_id        = "query"
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  display_name        = "Query"
  method              = "POST"
  url_template        = "/query"
  description         = "Query the RAG system"
  
  response {
    status_code = 200
  }
}

resource "azurerm_api_management_api_operation_policy" "query" {
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  operation_id        = azurerm_api_management_api_operation.query.operation_id
  
  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <cors>
      <allowed-origins>
        <origin>*</origin>
      </allowed-origins>
      <allowed-methods>
        <method>POST</method>
        <method>OPTIONS</method>
      </allowed-methods>
      <allowed-headers>
        <header>Content-Type</header>
        <header>Authorization</header>
      </allowed-headers>
    </cors>
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <openid-config url="https://login.microsoftonline.com/${var.aad_b2c_tenant_id}/v2.0/.well-known/openid-configuration?p=${var.aad_b2c_policy_name}" />
      <required-claims>
        <claim name="aud">
          <value>${var.aad_b2c_application_id}</value>
        </claim>
      </required-claims>
    </validate-jwt>
    <set-backend-service id="apim-generated-policy" backend-id="query-function" />
    <set-header name="x-functions-key" exists-action="override">
      <value>{{query-function-key}}</value>
    </set-header>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

# ====================================
# Upload operation
# ====================================

resource "azurerm_api_management_api_operation" "upload" {
  operation_id        = "upload"
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  display_name        = "Upload"
  method              = "POST"
   url_template        = "/upload"
  description         = "Upload documents to the RAG system"
  
  response {
    status_code = 200
  }
}

resource "azurerm_api_management_api_operation_policy" "upload" {
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  operation_id        = azurerm_api_management_api_operation.upload.operation_id
  
  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <cors>
      <allowed-origins>
        <origin>*</origin>
      </allowed-origins>
      <allowed-methods>
        <method>POST</method>
        <method>OPTIONS</method>
      </allowed-methods>
      <allowed-headers>
        <header>Content-Type</header>
        <header>Authorization</header>
      </allowed-headers>
    </cors>
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <openid-config url="https://login.microsoftonline.com/${var.aad_b2c_tenant_id}/v2.0/.well-known/openid-configuration?p=${var.aad_b2c_policy_name}" />
      <required-claims>
        <claim name="aud">
          <value>${var.aad_b2c_application_id}</value>
        </claim>
      </required-claims>
    </validate-jwt>
    <set-backend-service id="apim-generated-policy" backend-id="upload-function" />
    <set-header name="x-functions-key" exists-action="override">
      <value>{{upload-function-key}}</value>
    </set-header>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

# ====================================
# Function Backends for API Management
# ====================================

resource "azurerm_api_management_backend" "auth_function" {
  name                = "auth-function"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.main.name
  protocol            = "http"
  url                 = "https://${var.auth_handler_function_name}.azurewebsites.net/api/auth_handler"
  
  credentials {
    header = {
      "x-functions-key" = var.auth_handler_function_key
    }
  }
}

resource "azurerm_api_management_backend" "query_function" {
  name                = "query-function"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.main.name
  protocol            = "http"
  url                 = "https://${var.query_processor_function_name}.azurewebsites.net/api/query_processor"
}

resource "azurerm_api_management_backend" "upload_function" {
  name                = "upload-function"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.main.name
  protocol            = "http"
  url                 = "https://${var.upload_handler_function_name}.azurewebsites.net/api/upload_handler"
}

# ====================================
# APIM Named Values for Function Keys
# ====================================

resource "azurerm_api_management_named_value" "query_function_key" {
  name                = "query-function-key"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.main.name
  display_name        = "query-function-key"
  value               = var.query_processor_function_key
  secret              = true
}

resource "azurerm_api_management_named_value" "upload_function_key" {
  name                = "upload-function-key"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.main.name
  display_name        = "upload-function-key"
  value               = var.upload_handler_function_key
  secret              = true
}
# scripts/import_resources.sh

#!/bin/bash

# Get project variables
if [ "$#" -ge 1 ]; then
  PROJECT_NAME=$1
else
  # Try to get from terraform.tfvars
  PROJECT_NAME=$(grep project_name terraform.tfvars 2>/dev/null | cut -d '=' -f2 | tr -d ' "')
fi

if [ "$#" -ge 2 ]; then
  STAGE=$2
else
  # Try to get from terraform.tfvars
  STAGE=$(grep stage terraform.tfvars 2>/dev/null | cut -d '=' -f2 | tr -d ' "')
fi

if [ "$#" -ge 3 ]; then
  LOCATION=$3
else
  # Try to get from terraform.tfvars
  LOCATION=$(grep location terraform.tfvars 2>/dev/null | cut -d '=' -f2 | tr -d ' "')
fi

# Set default values if not found
PROJECT_NAME=${PROJECT_NAME}
STAGE=${STAGE}
LOCATION=${LOCATION}

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Starting resource import process for ${PROJECT_NAME}-${STAGE}..."
RESOURCE_GROUP="${PROJECT_NAME}-${STAGE}-rg"

# Function to check if resource is already in state
function check_state() {
  terraform state list | grep -q "$1"
  return $?
}

# ----------------------------------------
# Resource Group
# ----------------------------------------
echo -e "${YELLOW}Checking Resource Group: ${RESOURCE_GROUP}${NC}"
if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
  echo -e "${GREEN}Resource Group exists, checking state...${NC}"
  
  if check_state "azurerm_resource_group.main"; then
    echo -e "${GREEN}Resource Group already in state.${NC}"
  else
    echo -e "${YELLOW}Importing Resource Group...${NC}"
    terraform import "azurerm_resource_group.main" "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}"
  fi
else
  echo -e "${YELLOW}Resource Group doesn't exist, will be created by Terraform${NC}"
fi

# ----------------------------------------
# VNet
# ----------------------------------------
VNET_NAME="${PROJECT_NAME}-${STAGE}-vnet"
echo -e "${YELLOW}Checking VNet: ${VNET_NAME}${NC}"
if az network vnet show --resource-group "${RESOURCE_GROUP}" --name "${VNET_NAME}" &>/dev/null; then
  echo -e "${GREEN}VNet exists, checking state...${NC}"
  
  if check_state "module.network.azurerm_virtual_network.main"; then
    echo -e "${GREEN}VNet already in state.${NC}"
  else
    echo -e "${YELLOW}Importing VNet...${NC}"
    terraform import "module.network.azurerm_virtual_network.main" "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}"
  fi
else
  echo -e "${YELLOW}VNet doesn't exist, will be created by Terraform${NC}"
fi

# ----------------------------------------
# Storage Account
# ----------------------------------------
DOCUMENTS_STORAGE="${PROJECT_NAME}${STAGE}docs"
echo -e "${YELLOW}Checking Storage Account: ${DOCUMENTS_STORAGE}${NC}"
if az storage account show --name "${DOCUMENTS_STORAGE}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  echo -e "${GREEN}Storage Account exists, checking state...${NC}"
  
  if check_state "module.storage.azurerm_storage_account.documents"; then
    echo -e "${GREEN}Storage Account already in state.${NC}"
  else
    echo -e "${YELLOW}Importing Storage Account...${NC}"
    terraform import "module.storage.azurerm_storage_account.documents" "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${DOCUMENTS_STORAGE}"
  fi
else
  echo -e "${YELLOW}Storage Account doesn't exist, will be created by Terraform${NC}"
fi

# ----------------------------------------
# Cosmos DB
# ----------------------------------------
COSMOS_ACCOUNT="${PROJECT_NAME}${STAGE}metadata"
echo -e "${YELLOW}Checking Cosmos DB Account: ${COSMOS_ACCOUNT}${NC}"
if az cosmosdb show --name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  echo -e "${GREEN}Cosmos DB Account exists, checking state...${NC}"
  
  if check_state "module.storage.azurerm_cosmosdb_account.metadata"; then
    echo -e "${GREEN}Cosmos DB Account already in state.${NC}"
  else
    echo -e "${YELLOW}Importing Cosmos DB Account...${NC}"
    terraform import "module.storage.azurerm_cosmosdb_account.metadata" "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DocumentDB/databaseAccounts/${COSMOS_ACCOUNT}"
  fi
else
  echo -e "${YELLOW}Cosmos DB Account doesn't exist, will be created by Terraform${NC}"
fi

# ----------------------------------------
# PostgreSQL Server
# ----------------------------------------
POSTGRES_SERVER="${PROJECT_NAME}-${STAGE}-postgres"
echo -e "${YELLOW}Checking PostgreSQL Flexible Server: ${POSTGRES_SERVER}${NC}"
if az postgres flexible-server show --name "${POSTGRES_SERVER}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  echo -e "${GREEN}PostgreSQL Flexible Server exists, checking state...${NC}"
  
  if check_state "module.database.azurerm_postgresql_flexible_server.main"; then
    echo -e "${GREEN}PostgreSQL Flexible Server already in state.${NC}"
  else
    echo -e "${YELLOW}Importing PostgreSQL Flexible Server...${NC}"
    terraform import "module.database.azurerm_postgresql_flexible_server.main" "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DBforPostgreSQL/flexibleServers/${POSTGRES_SERVER}"
  fi
else
  echo -e "${YELLOW}PostgreSQL Flexible Server doesn't exist, will be created by Terraform${NC}"
fi

# ----------------------------------------
# Key Vault
# ----------------------------------------
KEY_VAULT="${PROJECT_NAME}-${STAGE}-kv"
echo -e "${YELLOW}Checking Key Vault: ${KEY_VAULT}${NC}"
if az keyvault show --name "${KEY_VAULT}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  echo -e "${GREEN}Key Vault exists, checking state...${NC}"
  
  if check_state "module.database.azurerm_key_vault.main"; then
    echo -e "${GREEN}Key Vault already in state.${NC}"
  else
    echo -e "${YELLOW}Importing Key Vault...${NC}"
    terraform import "module.database.azurerm_key_vault.main" "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT}"
  fi
else
  echo -e "${YELLOW}Key Vault doesn't exist, will be created by Terraform${NC}"
fi

# ----------------------------------------
# Function App
# ----------------------------------------
FUNCTION_APPS=(
  "${PROJECT_NAME}-${STAGE}-document-processor:module.compute.azurerm_linux_function_app.document_processor"
  "${PROJECT_NAME}-${STAGE}-query-processor:module.compute.azurerm_linux_function_app.query_processor"
  "${PROJECT_NAME}-${STAGE}-upload-handler:module.compute.azurerm_linux_function_app.upload_handler"
  "${PROJECT_NAME}-${STAGE}-db-init:module.compute.azurerm_linux_function_app.db_init"
  "${PROJECT_NAME}-${STAGE}-auth-handler:module.compute.azurerm_linux_function_app.auth_handler"
)

for FUNCTION_ITEM in "${FUNCTION_APPS[@]}"; do
  FUNCTION_NAME=$(echo $FUNCTION_ITEM | cut -d':' -f1)
  FUNCTION_STATE=$(echo $FUNCTION_ITEM | cut -d':' -f2)
  
  echo -e "${YELLOW}Checking Function App: ${FUNCTION_NAME}${NC}"
  if az functionapp show --name "${FUNCTION_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
    echo -e "${GREEN}Function App exists, checking state...${NC}"
    
    if check_state "${FUNCTION_STATE}"; then
      echo -e "${GREEN}Function App already in state.${NC}"
    else
      echo -e "${YELLOW}Importing Function App...${NC}"
      terraform import "${FUNCTION_STATE}" "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/sites/${FUNCTION_NAME}"
    fi
  else
    echo -e "${YELLOW}Function App doesn't exist, will be created by Terraform${NC}"
  fi
done

# ----------------------------------------
# API Management
# ----------------------------------------
API_NAME="${PROJECT_NAME}-${STAGE}-api"
echo -e "${YELLOW}Checking API Management: ${API_NAME}${NC}"
if az apim show --name "${API_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  echo -e "${GREEN}API Management exists, checking state...${NC}"
  
  if check_state "module.api.azurerm_api_management.main"; then
    echo -e "${GREEN}API Management already in state.${NC}"
  else
    echo -e "${YELLOW}Importing API Management...${NC}"
    terraform import "module.api.azurerm_api_management.main" "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${API_NAME}"
  fi
else
  echo -e "${YELLOW}API Management doesn't exist, will be created by Terraform${NC}"
fi

echo -e "${GREEN}Resource import process completed!${NC}"
echo -e "${YELLOW}Run 'terraform plan' to see if any differences still exist${NC}"
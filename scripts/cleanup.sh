# scripts/cleanup.sh

#!/bin/bash

# Azure RAG Application Cleanup Script
# This script removes all Azure resources created for the RAG application

# Set text colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Banner
echo -e "${YELLOW}"
echo "============================================================"
echo "         Azure RAG Application - Complete Cleanup Script     "
echo "============================================================"
echo -e "${NC}"

# Get project configuration
read -p "Enter your project name (default: rag-app): " PROJECT_NAME
PROJECT_NAME=${PROJECT_NAME:-rag-app}

read -p "Enter environment/stage (default: dev): " STAGE
STAGE=${STAGE:-dev}

read -p "Enter Azure location (default: eastus): " LOCATION
LOCATION=${LOCATION:-eastus}

echo -e "\n${YELLOW}This script will DELETE ALL resources for:"
echo -e "  Project: ${PROJECT_NAME}"
echo -e "  Stage: ${STAGE}"
echo -e "  Location: ${LOCATION}${NC}"
echo -e "${RED}WARNING: This action is IRREVERSIBLE and will delete ALL data!${NC}"
read -p "Are you sure you want to proceed? (yes/no): " CONFIRMATION

if [[ $CONFIRMATION != "yes" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo -e "\n${YELLOW}Starting cleanup process...${NC}"

# Check Azure CLI login status
if ! az account show &>/dev/null; then
    echo "You need to login to Azure first. Running 'az login'..."
    az login
fi

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "Using subscription: $SUBSCRIPTION_ID"

# Resource Group name
RESOURCE_GROUP="${PROJECT_NAME}-${STAGE}-rg"
B2C_RESOURCE_GROUP="${PROJECT_NAME}-${STAGE}-b2c-rg"
TFSTATE_RESOURCE_GROUP="${PROJECT_NAME}-${STAGE}-tfstate-rg"

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local resource_group=$3
    
    az $resource_type show --name "$resource_name" --resource-group "$resource_group" &>/dev/null
    return $?
}

# Function to delete a resource and wait for completion
delete_resource() {
    local resource_type=$1
    local resource_name=$2
    local resource_group=$3
    
    echo "Deleting $resource_type: $resource_name"
    
    # Check if resource exists
    if resource_exists "$resource_type" "$resource_name" "$resource_group"; then
        # Delete the resource
        az $resource_type delete --name "$resource_name" --resource-group "$resource_group" --yes
        
        # Wait for resource deletion (optional)
        echo "Waiting for deletion to complete..."
        for i in {1..30}; do
            if ! resource_exists "$resource_type" "$resource_name" "$resource_group"; then
                echo -e "${GREEN}Resource deleted successfully.${NC}"
                break
            fi
            
            echo "Still deleting... (attempt $i/30)"
            sleep 10
            
            if [ $i -eq 30 ]; then
                echo -e "${YELLOW}Resource might still be deleting. Moving on to next resource.${NC}"
            fi
        done
    else
        echo "Resource not found. Skipping."
    fi
}

# Delete main resource group and its resources
echo -e "\n${YELLOW}Checking for resource group: ${RESOURCE_GROUP}${NC}"
if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    echo "Resource group $RESOURCE_GROUP exists."
    
    # 1. Delete API Management first (it can take a long time)
    echo -e "\n${YELLOW}Deleting API Management...${NC}"
    API_NAME="${PROJECT_NAME}-${STAGE}-api"
    delete_resource "apim" "$API_NAME" "$RESOURCE_GROUP"
    
    # 2. Delete Function Apps
    echo -e "\n${YELLOW}Deleting Function Apps...${NC}"
    FUNCTION_APPS=(
        "${PROJECT_NAME}-${STAGE}-document-processor"
        "${PROJECT_NAME}-${STAGE}-query-processor"
        "${PROJECT_NAME}-${STAGE}-upload-handler"
        "${PROJECT_NAME}-${STAGE}-db-init"
        "${PROJECT_NAME}-${STAGE}-auth-handler"
    )
    
    for FUNCTION_APP in "${FUNCTION_APPS[@]}"; do
        delete_resource "functionapp" "$FUNCTION_APP" "$RESOURCE_GROUP"
    done
    
    # 3. Delete App Service Plan
    echo -e "\n${YELLOW}Deleting App Service Plan...${NC}"
    delete_resource "appservice plan" "${PROJECT_NAME}-${STAGE}-function-plan" "$RESOURCE_GROUP"
    
    # 4. Delete PostgreSQL server (this will delete all databases)
    echo -e "\n${YELLOW}Deleting PostgreSQL server...${NC}"
    delete_resource "postgres flexible-server" "${PROJECT_NAME}-${STAGE}-postgres" "$RESOURCE_GROUP"
    
    # 5. Delete Cosmos DB account
    echo -e "\n${YELLOW}Deleting Cosmos DB account...${NC}"
    delete_resource "cosmosdb" "${PROJECT_NAME}${STAGE}metadata" "$RESOURCE_GROUP"
    
    # 6. Delete storage accounts
    echo -e "\n${YELLOW}Deleting Storage Accounts...${NC}"
    STORAGE_ACCOUNTS=(
        "${PROJECT_NAME}${STAGE}docs"
        "${PROJECT_NAME}${STAGE}func"
        "${PROJECT_NAME}${STAGE}funcs"
    )
    
    for STORAGE_ACCOUNT in "${STORAGE_ACCOUNTS[@]}"; do
        delete_resource "storage account" "$STORAGE_ACCOUNT" "$RESOURCE_GROUP"
    done
    
    # 7. Delete Key Vault
    echo -e "\n${YELLOW}Deleting Key Vault...${NC}"
    # First, check for soft-deleted Key Vault instances
    KV_NAME="${PROJECT_NAME}-${STAGE}-kv"
    if az keyvault list-deleted --query "[?name=='$KV_NAME'].name" -o tsv | grep -q "$KV_NAME"; then
        echo "Purging soft-deleted Key Vault: $KV_NAME"
        az keyvault purge --name "$KV_NAME"
    fi
    delete_resource "keyvault" "$KV_NAME" "$RESOURCE_GROUP"
    
    # 8. Delete Application Insights
    echo -e "\n${YELLOW}Deleting Application Insights...${NC}"
    INSIGHTS=(
        "${PROJECT_NAME}-${STAGE}-app-insights"
        "${PROJECT_NAME}-${STAGE}-api-insights"
    )
    
    for INSIGHT in "${INSIGHTS[@]}"; do
        delete_resource "monitor app-insights component" "$INSIGHT" "$RESOURCE_GROUP"
    done
    
    # 9. Delete Log Analytics Workspaces
    echo -e "\n${YELLOW}Deleting Log Analytics Workspaces...${NC}"
    LOG_WORKSPACES=(
        "${PROJECT_NAME}-${STAGE}-log-analytics"
        "${PROJECT_NAME}-${STAGE}-law"
    )
    
    for WORKSPACE in "${LOG_WORKSPACES[@]}"; do
        delete_resource "monitor log-analytics workspace" "$WORKSPACE" "$RESOURCE_GROUP"
    done
    
    # 10. Delete Network Watcher
    echo -e "\n${YELLOW}Deleting Network Watcher...${NC}"
    delete_resource "network watcher" "${PROJECT_NAME}-${STAGE}-network-watcher" "$RESOURCE_GROUP"
    
    # 11. Delete Azure Bastion
    echo -e "\n${YELLOW}Deleting Azure Bastion...${NC}"
    delete_resource "network bastion" "${PROJECT_NAME}-${STAGE}-bastion" "$RESOURCE_GROUP"
    
    # 12. Delete Virtual Network
    echo -e "\n${YELLOW}Deleting VNet and related resources...${NC}"
    
    # Delete NSGs
    NSG_NAMES=(
        "${PROJECT_NAME}-${STAGE}-function-nsg"
        "${PROJECT_NAME}-${STAGE}-database-nsg"
        "${PROJECT_NAME}-${STAGE}-api-nsg"
    )
    
    for NSG_NAME in "${NSG_NAMES[@]}"; do
        delete_resource "network nsg" "$NSG_NAME" "$RESOURCE_GROUP"
    done
    
    # Delete NAT Gateway
    NAT_GATEWAY_NAMES=(
        "${PROJECT_NAME}-${STAGE}-nat-gateway-1"
        "${PROJECT_NAME}-${STAGE}-nat-gateway-2"
    )
    
    for NAT_NAME in "${NAT_GATEWAY_NAMES[@]}"; do
        delete_resource "network nat gateway" "$NAT_NAME" "$RESOURCE_GROUP"
    done
    
    # Delete public IPs
    PUBLIC_IP_NAMES=(
        "${PROJECT_NAME}-${STAGE}-nat-ip-1"
        "${PROJECT_NAME}-${STAGE}-nat-ip-2"
        "${PROJECT_NAME}-${STAGE}-bastion-ip"
    )
    
    for IP_NAME in "${PUBLIC_IP_NAMES[@]}"; do
        delete_resource "network public-ip" "$IP_NAME" "$RESOURCE_GROUP"
    done
    
    # Delete private DNS zone
    echo -e "\n${YELLOW}Deleting Private DNS Zone...${NC}"
    delete_resource "network private-dns zone" "privatelink.postgres.database.azure.com" "$RESOURCE_GROUP"
    
    # Delete Virtual Network
    delete_resource "network vnet" "${PROJECT_NAME}-${STAGE}-vnet" "$RESOURCE_GROUP"
    
    # Finally, delete the entire resource group
    echo -e "\n${YELLOW}Deleting the entire resource group: ${RESOURCE_GROUP}${NC}"
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    echo "Resource group deletion initiated. This may take several minutes to complete."
else
    echo -e "${YELLOW}Resource group $RESOURCE_GROUP not found.${NC}"
fi

# Delete B2C resource group (if it exists)
echo -e "\n${YELLOW}Checking for B2C resource group: ${B2C_RESOURCE_GROUP}${NC}"
if az group show --name "$B2C_RESOURCE_GROUP" &>/dev/null; then
    echo "B2C Resource group exists. Deleting..."
    az group delete --name "$B2C_RESOURCE_GROUP" --yes --no-wait
    echo "B2C Resource group deletion initiated."
else
    echo "B2C Resource group not found. Skipping."
fi

# Delete Terraform state storage
echo -e "\n${YELLOW}Checking for Terraform state resource group: ${TFSTATE_RESOURCE_GROUP}${NC}"
if az group show --name "$TFSTATE_RESOURCE_GROUP" &>/dev/null; then
    echo "Terraform state resource group exists."
    
    # Get storage account name
    TFSTATE_STORAGE="${PROJECT_NAME}${STAGE}tfstate"
    
    # Empty the storage container before deleting
    echo "Emptying Terraform state container..."
    az storage container list --account-name "$TFSTATE_STORAGE" --query "[].name" -o tsv --auth-mode login | while read CONTAINER; do
        echo "Emptying container: $CONTAINER"
        az storage blob delete-batch --account-name "$TFSTATE_STORAGE" --source "$CONTAINER" --auth-mode login || true
    done
    
    # Delete the resource group
    echo "Deleting Terraform state resource group..."
    az group delete --name "$TFSTATE_RESOURCE_GROUP" --yes --no-wait
    echo "Terraform state resource group deletion initiated."
else
    echo "Terraform state resource group not found. Skipping."
fi

echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}    Cleanup Process Completed                     ${NC}"
echo -e "${GREEN}==================================================${NC}"
echo -e "${YELLOW}Resources that were targeted for deletion:${NC}"
echo "- API Management: ${PROJECT_NAME}-${STAGE}-api"
echo "- Function Apps for ${PROJECT_NAME}-${STAGE}"
echo "- PostgreSQL Server: ${PROJECT_NAME}-${STAGE}-postgres"
echo "- Cosmos DB: ${PROJECT_NAME}${STAGE}metadata"
echo "- Storage Accounts for documents, functions, etc."
echo "- Key Vault: ${PROJECT_NAME}-${STAGE}-kv"
echo "- Application Insights and Log Analytics Workspaces"
echo "- Network resources: VNet, NSGs, NAT Gateway, etc."
echo "- Resource Groups: Main, B2C, and Terraform state"
echo -e "\n${YELLOW}Note: Some resources may take time to fully delete.${NC}"
echo -e "${YELLOW}Check the Azure Portal to verify all resources have been removed.${NC}"
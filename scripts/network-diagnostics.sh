# scripts/network-diagnostics.sh

#!/bin/bash
# Simple Network Connectivity Check for PostgreSQL
# Usage: ./network-diagnostics.sh <environment> [location] <project_name>

set -e

# Default values
LOCATION=${2}
PROJECT_NAME=${3}
ENV=$1

# Check if environment was provided
if [ -z "$ENV" ]; then
  echo "Error: Environment not specified"
  echo "Usage: $0 <environment> [location]"
  echo "Example: $0 dev eastus"
  exit 1
fi

echo "Running network diagnostics for $PROJECT_NAME-$ENV in $LOCATION"

# Get PostgreSQL server FQDN
echo "Getting PostgreSQL server FQDN..."
SERVER_NAME="${PROJECT_NAME}-${ENV}-postgres"
RESOURCE_GROUP="${PROJECT_NAME}-${ENV}-rg"

DB_FQDN=$(az postgres flexible-server show \
  --name "$SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "fullyQualifiedDomainName" \
  --output tsv 2>/dev/null || echo "not-found")

if [ "$DB_FQDN" == "not-found" ] || [ -z "$DB_FQDN" ]; then
  echo "Error: PostgreSQL server not found!"
  exit 1
fi

echo "PostgreSQL FQDN: $DB_FQDN"

# Get VNet ID
echo "Getting VNet ID..."
VNET_NAME="${PROJECT_NAME}-${ENV}-vnet"
VNET_ID=$(az network vnet show \
  --name "$VNET_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "id" \
  --output tsv 2>/dev/null || echo "not-found")

if [ -z "$VNET_ID" ]; then
  echo "Error: VNet not found!"
  exit 1
fi

echo "VNet ID: $VNET_ID"

# Get Function subnet NSG
echo "Getting Function Subnet NSG..."
FUNCTION_NSG_NAME="${PROJECT_NAME}-${ENV}-function-nsg"
FUNCTION_NSG_ID=$(az network nsg show \
  --name "$FUNCTION_NSG_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "id" \
  --output tsv 2>/dev/null || echo "not-found")

echo "Function NSG ID: $FUNCTION_NSG_ID"

# Get DB subnet NSG
echo "Getting DB Subnet NSG..."
DB_NSG_NAME="${PROJECT_NAME}-${ENV}-database-nsg"
DB_NSG_ID=$(az network nsg show \
  --name "$DB_NSG_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "id" \
  --output tsv 2>/dev/null || echo "not-found")

echo "DB NSG ID: $DB_NSG_ID"

# Check DB NSG inbound rules
echo -e "\nDB Subnet NSG Inbound Rules:"
az network nsg rule list \
  --nsg-name "$DB_NSG_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?direction=='Inbound'].{Name:name, Priority:priority, SourceAddressPrefix:sourceAddressPrefix, DestinationPortRange:destinationPortRange, Protocol:protocol, Access:access}" \
  --output table

# Check Function NSG outbound rules
echo -e "\nFunction NSG Outbound Rules:"
az network nsg rule list \
  --nsg-name "$FUNCTION_NSG_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?direction=='Outbound'].{Name:name, Priority:priority, DestinationAddressPrefix:destinationAddressPrefix, DestinationPortRange:destinationPortRange, Protocol:protocol, Access:access}" \
  --output table

# Check DNS resolution from a test VM
echo -e "\nChecking if we can create a test VM for network diagnostics..."
TEST_VM_NAME="${PROJECT_NAME}-${ENV}-test-vm"

# Check if test VM exists
VM_EXISTS=$(az vm show --name "$TEST_VM_NAME" --resource-group "$RESOURCE_GROUP" --query "name" --output tsv 2>/dev/null || echo "")

if [ -z "$VM_EXISTS" ]; then
  echo "No test VM found. Would you like to create a temporary VM to test connectivity? (yes/no)"
  read CREATE_VM
  
  if [ "$CREATE_VM" == "yes" ]; then
    echo "Creating temporary test VM in Function subnet..."
    
    # Get Function subnet ID
    FUNCTION_SUBNET_ID=$(az network vnet subnet show \
      --name "${PROJECT_NAME}-${ENV}-function-subnet" \
      --vnet-name "$VNET_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --query "id" \
      --output tsv)
    
    # Create VM
    az vm create \
      --resource-group "$RESOURCE_GROUP" \
      --name "$TEST_VM_NAME" \
      --image UbuntuLTS \
      --admin-username azureuser \
      --generate-ssh-keys \
      --subnet "$FUNCTION_SUBNET_ID" \
      --public-ip-address "" \
      --size Standard_B1s \
      --no-wait
    
    echo "VM creation started. It will take a few minutes to complete."
    echo "Please run this script again after the VM is created to continue with diagnostics."
    exit 0
  else
    echo "Skipping connectivity tests that require a VM."
  fi
else
  echo "Found test VM: $TEST_VM_NAME"
  
  # Run DNS resolution test on VM
  echo "Testing DNS resolution for $DB_FQDN from test VM..."
  
  DNS_TEST=$(az vm run-command invoke \
    --resource-group "$RESOURCE_GROUP" \
    --name "$TEST_VM_NAME" \
    --command-id RunShellScript \
    --scripts "nslookup $DB_FQDN" \
    --query "value[0].message" \
    --output tsv)
  
  echo -e "\nDNS Resolution Test Result:"
  echo "$DNS_TEST"
  
  # Run connectivity test on VM
  echo -e "\nTesting TCP connectivity to PostgreSQL port 5432..."
  
  CONN_TEST=$(az vm run-command invoke \
    --resource-group "$RESOURCE_GROUP" \
    --name "$TEST_VM_NAME" \
    --command-id RunShellScript \
    --scripts "timeout 5 nc -zv $DB_FQDN 5432 || echo 'Connection failed'" \
    --query "value[0].message" \
    --output tsv)
  
  echo -e "Connectivity Test Result:"
  echo "$CONN_TEST"
  
  # Offer to clean up test VM
  echo -e "\nWould you like to delete the test VM now? (yes/no)"
  read DELETE_VM
  
  if [ "$DELETE_VM" == "yes" ]; then
    echo "Deleting test VM..."
    az vm delete \
      --resource-group "$RESOURCE_GROUP" \
      --name "$TEST_VM_NAME" \
      --yes
    
    # Also delete related resources
    echo "Cleaning up related resources..."
    az disk delete \
      --resource-group "$RESOURCE_GROUP" \
      --name "${TEST_VM_NAME}_OsDisk_1_*" \
      --yes
    
    az network nic delete \
      --resource-group "$RESOURCE_GROUP" \
      --name "${TEST_VM_NAME}VMNic"
    
    echo "Test VM and related resources deleted."
  fi
fi

# Check PostgreSQL server status
echo -e "\nPostgreSQL Server Status:"
az postgres flexible-server show \
  --name "$SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "{Name:name, Status:userVisibleState, Version:version, Location:location}" \
  --output table

# Get Key Vault name
KEY_VAULT_NAME="${PROJECT_NAME}-${ENV}-kv"
KV_EXISTS=$(az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" --query "name" --output tsv 2>/dev/null || echo "")

if [ -n "$KV_EXISTS" ]; then
  echo -e "\nChecking Key Vault secret for database credentials..."
  
  DB_SECRET_EXISTS=$(az keyvault secret list \
    --vault-name "$KEY_VAULT_NAME" \
    --query "[?name=='db-credentials'].name" \
    --output tsv)
  
  if [ -n "$DB_SECRET_EXISTS" ]; then
    echo "✅ Database credentials secret exists in Key Vault"
  else
    echo "❌ Database credentials secret not found in Key Vault"
  fi
else
  echo "❌ Key Vault not found: $KEY_VAULT_NAME"
fi

# Summary
echo -e "\nConnectivity Check Summary:"
echo "1. PostgreSQL FQDN: $DB_FQDN"
echo "2. VNet ID: $VNET_ID"
echo "3. Function NSG: $FUNCTION_NSG_ID"
echo "4. DB NSG: $DB_NSG_ID"

echo -e "\nRecommendations:"
echo "1. Check that the Key Vault secret has the correct connection details"
echo "2. Ensure DB NSG allows inbound traffic from Function subnet on port 5432"
echo "3. Ensure Function NSG allows outbound traffic to DB subnet on port 5432"
echo "4. Verify that all resources are in the same Virtual Network"
echo "5. Check that the private DNS zone is properly configured"
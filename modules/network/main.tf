# =========================
# Network Module for RAG Application
# =========================
# Creates a Virtual Network with public/private subnets, NAT gateways, and security groups

# =========================
# Locals
# =========================

locals {
  name = "${var.project_name}-${var.stage}"

  common_tags = {
    Project     = var.project_name
    Environment = var.stage
    ManagedBy   = "Terraform"
  }
}

# =========================
# Virtual Network & Internet Gateway
# =========================

resource "azurerm_virtual_network" "main" {
  name                = "${local.name}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.address_space]

  tags = merge(
    { Name = "${local.name}-vnet" },
    local.common_tags
  )

  lifecycle {
    prevent_destroy = true
  }
}

# =========================
# Subnets
# =========================

resource "azurerm_subnet" "function" {
  name                 = "${local.name}-function-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_prefixes["function"]]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault", "Microsoft.Web", "Microsoft.AzureCosmosDB"]
  delegation {
    name = "functiondelegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "database" {
  name                 = "${local.name}-database-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_prefixes["database"]]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
  delegation {
    name = "dbdelegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "api" {
  name                 = "${local.name}-api-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_prefixes["api"]]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault", "Microsoft.Web"]
  delegation {
    name = "apidelegation"
    service_delegation {
      name    = "Microsoft.ApiManagement/service"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "bastion" {
  count                = var.create_bastion ? 1 : 0
  name                 = "AzureBastionSubnet" # Must be exactly this name for Azure Bastion
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_prefixes["bastion"]]
}

# =========================
# NAT Gateway
# =========================

resource "azurerm_public_ip" "nat" {
  count               = var.single_nat_gateway ? 1 : 2
  name                = "${local.name}-nat-ip-${count.index + 1}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = merge(
    { Name = "${local.name}-nat-ip-${count.index + 1}" },
    local.common_tags
  )
}

resource "azurerm_nat_gateway" "main" {
  count               = var.single_nat_gateway ? 1 : 2
  name                = "${local.name}-nat-gateway-${count.index + 1}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Standard"

  tags = merge(
    { Name = "${local.name}-nat-gateway-${count.index + 1}" },
    local.common_tags
  )
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  count                = var.single_nat_gateway ? 1 : 2
  nat_gateway_id       = azurerm_nat_gateway.main[count.index].id
  public_ip_address_id = azurerm_public_ip.nat[count.index].id
}

resource "azurerm_subnet_nat_gateway_association" "function" {
  subnet_id      = azurerm_subnet.function.id
  nat_gateway_id = azurerm_nat_gateway.main[0].id
}

resource "azurerm_subnet_nat_gateway_association" "api" {
  subnet_id      = azurerm_subnet.api.id
  nat_gateway_id = var.single_nat_gateway ? azurerm_nat_gateway.main[0].id : azurerm_nat_gateway.main[1].id
}

# =========================
# Network Security Groups
# =========================

resource "azurerm_network_security_group" "function" {
  name                = "${local.name}-function-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "AllowAzureServices"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureCloud"
    destination_address_prefix = "*"
  }

  tags = merge(
    { Name = "${local.name}-function-nsg" },
    local.common_tags
  )
}

resource "azurerm_network_security_group" "database" {
  name                = "${local.name}-database-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "AllowPostgreSQL"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = var.subnet_prefixes["function"]
    destination_address_prefix = "*"
  }

  tags = merge(
    { Name = "${local.name}-database-nsg" },
    local.common_tags
  )
}

resource "azurerm_network_security_group" "api" {
  name                = "${local.name}-api-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "AllowHTTPSInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = merge(
    { Name = "${local.name}-api-nsg" },
    local.common_tags
  )
}

# =========================
# Network Security Group Associations
# =========================

resource "azurerm_subnet_network_security_group_association" "function" {
  subnet_id                 = azurerm_subnet.function.id
  network_security_group_id = azurerm_network_security_group.function.id
}

resource "azurerm_subnet_network_security_group_association" "database" {
  subnet_id                 = azurerm_subnet.database.id
  network_security_group_id = azurerm_network_security_group.database.id
}

resource "azurerm_subnet_network_security_group_association" "api" {
  subnet_id                 = azurerm_subnet.api.id
  network_security_group_id = azurerm_network_security_group.api.id
}

# =========================
# Azure Bastion (conditionally created)
# =========================

resource "azurerm_public_ip" "bastion" {
  count               = var.create_bastion ? 1 : 0
  name                = "${local.name}-bastion-ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = merge(
    { Name = "${local.name}-bastion-ip" },
    local.common_tags
  )
}

resource "azurerm_bastion_host" "main" {
  count               = var.create_bastion ? 1 : 0
  name                = "${local.name}-bastion"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }

  tags = merge(
    { Name = "${local.name}-bastion" },
    local.common_tags
  )
}

# =========================
# Network Watcher Flow Logs
# =========================

resource "azurerm_network_watcher" "main" {
  count               = var.enable_flow_logs ? 1 : 0
  name                = "${local.name}-network-watcher"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(
    { Name = "${local.name}-network-watcher" },
    local.common_tags
  )
}

resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_flow_logs ? 1 : 0
  name                = "${local.name}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = merge(
    { Name = "${local.name}-law" },
    local.common_tags
  )
}

resource "azurerm_storage_account" "flow_logs" {
  count                    = var.enable_flow_logs ? 1 : 0
  name                     = "${var.project_name}${var.stage}flowlogs"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = local.common_tags
}

resource "azurerm_network_watcher_flow_log" "main" {
  count                = var.enable_flow_logs ? 1 : 0
  network_watcher_name = azurerm_network_watcher.main[0].name
  resource_group_name  = var.resource_group_name
  name                 = "${local.name}-flow-log"

  network_security_group_id = azurerm_network_security_group.function.id
  storage_account_id        = azurerm_storage_account.flow_logs[0].id
  enabled                   = true
  version                   = 2

  retention_policy {
    enabled = true
    days    = 7
  }
}
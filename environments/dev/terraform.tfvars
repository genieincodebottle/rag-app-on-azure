# =========================
# Root terraform.tfvars
# =========================

# -------------------------
# Project Settings
# -------------------------
project_name = "rag-app"
stage        = "dev"
location     = "eastus"

# -------------------------
# Function Settings
# -------------------------
function_memory_size = 512
function_timeout     = 150

# -------------------------
# GitHub Repository Settings
# -------------------------
github_repo   = "genieincodebottle/rag-app-on-azure"
github_branch = "develop"

# -------------------------
# Monitoring
# -------------------------
alert_email = "rajsrivastava2@gmail.com"

# -------------------------
# Network Settings
# -------------------------
address_space       = "10.0.0.0/16"
subnet_prefixes     = {
  function  = "10.0.0.0/24"
  database  = "10.0.1.0/24"
  api       = "10.0.2.0/24"
  bastion   = "10.0.3.0/24"
}
single_nat_gateway  = true        # Cost saving for dev environment
enable_flow_logs    = false       # Only needed for prod
create_bastion      = true        # Useful for dev environment
bastion_allowed_cidr = ["0.0.0.0/0"]  # Restrict this in production

# -------------------------
# Storage Settings
# -------------------------
enable_lifecycle_rules    = false  # Only enable in prod
standard_ia_transition_days = 90
archive_transition_days     = 365

# -------------------------
# Database Settings
# -------------------------
db_sku_name       = "B_Gen5_1"
db_storage_mb     = 5120
db_name           = "ragapp"
db_username       = "ragadmin"
reset_db_password = false  # Only set to true when you need to reset the password
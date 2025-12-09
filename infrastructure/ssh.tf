resource "random_pet" "ssh_key_name" {
  prefix    = "ssh"
  separator = ""
}

resource "random_password" "mongo_admin_pwd" {
  length  = 16
  special = false
}

resource "random_password" "mongo_appuser_pwd" {
  length  = 16
  special = false
}

resource "random_password" "grafana_pwd" {
  length  = 16
  special = false
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                          = "odl1986716KeyVault"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = true
}

resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = "8659ba1e-7d54-46a4-975b-9aebf6a33a57"
}

resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = "8659ba1e-7d54-46a4-975b-9aebf6a33a57"
}

resource "azurerm_role_assignment" "sp_kv_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "kv_sp_assignment" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azapi_resource_action" "ssh_public_key_gen" {
  type        = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  resource_id = azapi_resource.ssh_public_key.id
  action      = "generateKeyPair"
  method      = "POST"

  response_export_values = ["publicKey", "privateKey"]

  depends_on = [azurerm_key_vault.kv, azurerm_role_assignment.sp_kv_secrets_user, azurerm_role_assignment.kv_sp_assignment]
}

resource "azapi_resource" "ssh_public_key" {
  type      = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  name      = random_pet.ssh_key_name.id
  location  = azurerm_resource_group.rg.location
  parent_id = azurerm_resource_group.rg.id

  depends_on = [azurerm_key_vault.kv, azurerm_role_assignment.sp_kv_secrets_user, azurerm_role_assignment.kv_sp_assignment]
}

# Store the generated public key
resource "azurerm_key_vault_secret" "ssh_public_key" {
  name         = "vm-ssh-public-key"
  value        = azapi_resource_action.ssh_public_key_gen.output.publicKey
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [azurerm_key_vault.kv, azurerm_role_assignment.sp_kv_secrets_user, azurerm_role_assignment.kv_sp_assignment]
}

# Store the generated private key
resource "azurerm_key_vault_secret" "ssh_private_key" {
  name         = "vm-ssh-private-key"
  value        = azapi_resource_action.ssh_public_key_gen.output.privateKey
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [azurerm_key_vault.kv, azurerm_role_assignment.sp_kv_secrets_user, azurerm_role_assignment.kv_sp_assignment]
}

resource "azurerm_key_vault_secret" "mongo_admin_pwd" {
  name         = "mongodb-admin-pwd"
  value        = random_password.mongo_admin_pwd.result
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [azurerm_key_vault.kv, azurerm_role_assignment.sp_kv_secrets_user, azurerm_role_assignment.kv_sp_assignment]
}

resource "azurerm_key_vault_secret" "mongo_appuser_pwd" {
  name         = "mongodb-appuser-pwd"
  value        = random_password.mongo_appuser_pwd.result
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [azurerm_key_vault.kv, azurerm_role_assignment.sp_kv_secrets_user, azurerm_role_assignment.kv_sp_assignment]
}

resource "azurerm_key_vault_secret" "mongo_db_url" {
  name         = "mongodb-url"
  value        = jsonencode({ "url" : "mongodb://appuser:${random_password.mongo_appuser_pwd.result}@wiz-exercise-mongodb:27017/go-mongodb?authSource=go-mongodb" })
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [azurerm_key_vault.kv, azurerm_role_assignment.sp_kv_secrets_user, azurerm_role_assignment.kv_sp_assignment]
}

resource "azurerm_key_vault_secret" "grafana_pwd" {
  name         = "grafana-pwd"
  value        = random_password.grafana_pwd.result
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [azurerm_key_vault.kv, azurerm_role_assignment.sp_kv_secrets_user, azurerm_role_assignment.kv_sp_assignment]
}

resource "azurerm_monitor_diagnostic_setting" "kv_logging" {
  name                       = "kv-logging"
  target_resource_id         = azurerm_key_vault.kv.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  # Enable Key Vault logs
  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AllLogs"
  }

  # Enable metrics
  enabled_metric {
    category = "AllMetrics"

  }
}

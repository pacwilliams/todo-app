resource "random_pet" "ssh_key_name" {
  prefix    = "ssh"
  separator = ""
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                = "odl1986716KeyVault"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions    = ["Get", "List", "Create", "Delete"]
    secret_permissions = ["Get", "List", "Set", "Delete"]
  }
}

resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = "8659ba1e-7d54-46a4-975b-9aebf6a33a57" 
}

resource "azurerm_role_assignment" "sp_kv_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azapi_resource_action" "ssh_public_key_gen" {
  type        = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  resource_id = azapi_resource.ssh_public_key.id
  action      = "generateKeyPair"
  method      = "POST"

  response_export_values = ["publicKey", "privateKey"]

  depends_on = [azurerm_key_vault.kv]
}

resource "azapi_resource" "ssh_public_key" {
  type      = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  name      = random_pet.ssh_key_name.id
  location  = azurerm_resource_group.rg.location
  parent_id = azurerm_resource_group.rg.id

  depends_on = [azurerm_key_vault.kv]
}

# Store the generated public key
resource "azurerm_key_vault_secret" "ssh_public_key" {
  name         = "aks-ssh-public-key"
  value        = azapi_resource_action.ssh_public_key_gen.output.publicKey
  key_vault_id = azurerm_key_vault.kv.id
}

# Store the generated private key
resource "azurerm_key_vault_secret" "ssh_private_key" {
  name         = "aks-ssh-private-key"
  value        = azapi_resource_action.ssh_public_key_gen.output.privateKey
  key_vault_id = azurerm_key_vault.kv.id
}

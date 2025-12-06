resource "random_pet" "ssh_key_name" {
  prefix    = "ssh"
  separator = ""
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                        = "${azurerm_resource_group.rg.name}-KeyVault"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions    = ["get", "list", "create", "delete"]
    secret_permissions = ["get", "list", "set", "delete"]
  }
}

resource "azapi_resource_action" "ssh_public_key_gen" {
  type        = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  resource_id = azapi_resource.ssh_public_key.id
  action      = "generateKeyPair"
  method      = "POST"

  response_export_values = ["publicKey", "privateKey"]
}

resource "azapi_resource" "ssh_public_key" {
  type      = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  name      = random_pet.ssh_key_name.id
  location  = azurerm_resource_group.rg.location
  parent_id = azurerm_resource_group.rg.id
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

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
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  public_network_access_enabled = false
  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
  }
}
resource "azurerm_private_endpoint" "kv_pe" {
  name                = "kv-private-endpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.subnet_1.id

  private_service_connection {
    name                           = "kv-connection"
    private_connection_resource_id = azurerm_key_vault.kv.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }
}

resource "azurerm_private_dns_zone" "kv_dns" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv_dns_link" {
  name                  = "kv-dns-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.kv_dns.name
  virtual_network_id    = azurerm_virtual_network.my_terraform_network.id
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

  depends_on = [azurerm_key_vault.kv,azurerm_role_assignment.sp_kv_secrets_user,azurerm_role_assignment.kv_sp_assignment,azurerm_private_endpoint.kv_pe]
}

resource "azapi_resource" "ssh_public_key" {
  type      = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  name      = random_pet.ssh_key_name.id
  location  = azurerm_resource_group.rg.location
  parent_id = azurerm_resource_group.rg.id

  depends_on = [azurerm_key_vault.kv,azurerm_role_assignment.sp_kv_secrets_user,azurerm_role_assignment.kv_sp_assignment,azurerm_private_endpoint.kv_pe]
}

# Store the generated public key
resource "azurerm_key_vault_secret" "ssh_public_key" {
  name         = "vm-ssh-public-key"
  value        = azapi_resource_action.ssh_public_key_gen.output.publicKey
  key_vault_id = azurerm_key_vault.kv.id
  depends_on = [azurerm_key_vault.kv,azurerm_role_assignment.sp_kv_secrets_user,azurerm_role_assignment.kv_sp_assignment,azurerm_private_endpoint.kv_pe]
}

# Store the generated private key
resource "azurerm_key_vault_secret" "ssh_private_key" {
  name         = "vm-ssh-private-key"
  value        = azapi_resource_action.ssh_public_key_gen.output.privateKey
  key_vault_id = azurerm_key_vault.kv.id
  depends_on = [azurerm_key_vault.kv,azurerm_role_assignment.sp_kv_secrets_user,azurerm_role_assignment.kv_sp_assignment,azurerm_private_endpoint.kv_pe]
}

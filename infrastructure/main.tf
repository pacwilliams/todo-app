resource "azurerm_resource_group" "rg" {
  location = var.resource_group_location
  name     = "ODL-candidate-sandbox-02-1986716"
}

# Management lock to prevent accidental deletion of resource group
resource "azurerm_management_lock" "rg_lock" {
  name       = "rg-delete-lock"
  scope      = azurerm_resource_group.rg.id
  lock_level = "CanNotDelete"
  notes      = "Prevent accidental deletion of resource group"

  # Ensure the lock is destroyed before the resource group
  depends_on = [azurerm_resource_group.rg]
}

# Virtual Network
resource "azurerm_virtual_network" "my_terraform_network" {
  name                = "${azurerm_resource_group.rg.name}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

}
# Subnet(s)
resource "azurerm_subnet" "subnet_1" {
  name                 = "subnet-1"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.my_terraform_network.name
  address_prefixes     = ["10.0.1.0/24"]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.KeyVault"]
}

resource "azurerm_subnet" "subnet_2" {
  name                            = "subnet-2"
  resource_group_name             = azurerm_resource_group.rg.name
  virtual_network_name            = azurerm_virtual_network.my_terraform_network.name
  address_prefixes                = ["10.0.2.0/24"]
  default_outbound_access_enabled = false
  service_endpoints               = ["Microsoft.Storage", "Microsoft.KeyVault"]
}


# Create public IPs
resource "azurerm_public_ip" "my_terraform_public_ip" {
  name                = "${azurerm_resource_group.rg.name}-PublicIP"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "subnet2_nsg" {
  name                = "${azurerm_resource_group.rg.name}-NSG"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow_MongoDB"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "27017"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "10.0.2.0/24"
  }


}

resource "azurerm_subnet_network_security_group_association" "subnet2_nsg" {
  subnet_id                 = azurerm_subnet.subnet_2.id
  network_security_group_id = azurerm_network_security_group.subnet2_nsg.id
}

# Create network interface
resource "azurerm_network_interface" "my_terraform_nic" {
  name                = "${azurerm_resource_group.rg.name}-NIC"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "${azurerm_resource_group.rg.name}_nic_configuration"
    subnet_id                     = azurerm_subnet.subnet_2.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.my_terraform_public_ip.id
  }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "example" {
  network_interface_id      = azurerm_network_interface.my_terraform_nic.id
  network_security_group_id = azurerm_network_security_group.subnet2_nsg.id
}


# Create storage account for boot diagnostics
resource "azurerm_storage_account" "sa" {
  name                          = "odl1986716"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  account_tier                  = "Standard"
  access_tier                   = "Cold"
  account_replication_type      = "LRS"
  shared_access_key_enabled     = true
  public_network_access_enabled = true
  blob_properties {
    delete_retention_policy {
      days                     = 7
      permanent_delete_enabled = true
    }

  }
  network_rules {
    default_action = "Allow"
  }
}
resource "azurerm_storage_management_policy" "example" {
  storage_account_id = azurerm_storage_account.sa.id

  rule {
    name    = "delete-backups"
    enabled = true

    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["mongodb-backups/"]
    }

    actions {
      base_blob {

        delete_after_days_since_creation_greater_than = 30 # keep for 30 days

      }
    }
  }
}


resource "azurerm_storage_container" "backups" {
  name                  = "mongodb-backups"
  storage_account_id    = azurerm_storage_account.sa.id
  container_access_type = "private"
}

# Management lock to prevent accidental deletion of storage account
resource "azurerm_management_lock" "sa_lock" {
  name       = "storage-delete-lock"
  scope      = azurerm_storage_account.sa.id
  lock_level = "CanNotDelete"
  notes      = "Prevent accidental deletion of storage account"

  # Ensure the lock is destroyed before the storage account
  depends_on = [azurerm_storage_account.sa]
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "my_terraform_vm" {
  name                  = "${azurerm_resource_group.rg.name}-VM"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.my_terraform_nic.id]
  size                  = "Standard_DS1_v2"

  identity {
    type = "SystemAssigned"
  }



  os_disk {
    name                 = "${azurerm_resource_group.rg.name}-OsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  computer_name                   = "wiz-exercise-mongodb"
  admin_username                  = var.username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.username
    public_key = azapi_resource_action.ssh_public_key_gen.output.publicKey
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.sa.primary_blob_endpoint
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init-mongo.yaml", {
    key_vault_name = azurerm_key_vault.kv.name
    admin_secret   = "mongodb-admin-pwd"
    app_secret     = "mongodb-appuser-pwd"
  }))

  depends_on = [azurerm_key_vault.kv, azurerm_role_assignment.sp_kv_secrets_user, azurerm_role_assignment.kv_sp_assignment]
}
resource "azurerm_key_vault_access_policy" "vm_policy" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_virtual_machine.my_terraform_vm.identity[0].principal_id

  secret_permissions = ["Get", "List"]

  depends_on = [azurerm_linux_virtual_machine.my_terraform_vm, azurerm_key_vault.kv]
}

# Role assignment: grant VM identity access to secrets
resource "azurerm_role_assignment" "vm_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.my_terraform_vm.identity[0].principal_id
}


resource "azurerm_role_assignment" "vm_storage_blob_contributor" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_virtual_machine.my_terraform_vm.identity[0].principal_id
}

resource "azurerm_role_assignment" "vm_contributor" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_linux_virtual_machine.my_terraform_vm.identity[0].principal_id
}

# Create Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "odl1986716"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
}

# Management lock to prevent accidental deletion of resource group
resource "azurerm_management_lock" "acr_lock" {
  name       = "acr-delete-lock"
  scope      = azurerm_container_registry.acr.id
  lock_level = "CanNotDelete"
  notes      = "Prevent accidental deletion of resource group"

  # Ensure the lock is destroyed before the resource group
  depends_on = [azurerm_container_registry.acr]
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks_cluster" {
  name                = "${azurerm_resource_group.rg.name}-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "pwakscluster"

  default_node_pool {
    type                   = "VirtualMachineScaleSets"
    name                   = "default"
    node_count             = 1
    max_count              = 3
    min_count              = 1
    vm_size                = "Standard_DS2_v2"
    auto_scaling_enabled   = true
    node_public_ip_enabled = false
    vnet_subnet_id         = azurerm_subnet.subnet_1.id
    upgrade_settings {
      drain_timeout_in_minutes      = 90
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    service_cidr      = "10.3.0.0/16"
    dns_service_ip    = "10.3.0.10"

  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "Production"
  }
}

#Create Service Account
resource "kubernetes_service_account_v1" "todo_app" {
  metadata {
    name      = "todo-app-sa"
    namespace = "default"
  }
}

# Bind Role to Service Account
resource "kubernetes_cluster_role_binding_v1" "todo_app_admin" {
  metadata {
    name = "todo-app-admin-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.todo_app.metadata[0].name
    namespace = kubernetes_service_account_v1.todo_app.metadata[0].namespace
  }
}

resource "helm_release" "nginx_ingress" {
  name             = "nginx-ingress"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  set = [
    {
      name  = "controller.service.type"
      value = "LoadBalancer"
    },
    {
      name  = "controller.extraArgs.default-ssl-certificate"
      value = "ingress-nginx/wildcard-pw-az-demo-tls"
    },
    {
      # Azure-specific annotation to change probe path
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path"
      value = "/healthz"
    },
    {
      # Ingress-nginx config override so NGINX responds with 200 OK
      name  = "controller.config.health-check-path"
      value = "/healthz"
    }
  ]

  depends_on = [azurerm_kubernetes_cluster.aks_cluster]
}

data "kubernetes_service_v1" "nginx_ingress" {
  metadata {
    name      = "nginx-ingress-ingress-nginx-controller" # actual service name
    namespace = "ingress-nginx"
  }
}

# resource "cloudflare_dns_record" "todo" {
#   zone_id = var.zone_id
#   name    = "*"
#   content = data.kubernetes_service_v1.nginx_ingress.status[0].load_balancer[0].ingress[0].ip
#   type    = "A"
#   ttl     = 3600
#   proxied = false

#   depends_on = [helm_release.nginx_ingress]
# }

# Helm release for Cert-Manager
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true

  set = [
    {
      name  = "installCRDs"
      value = "true"
    }
  ]
  depends_on = [azurerm_kubernetes_cluster.aks_cluster]
}

resource "kubernetes_secret_v1" "cloudflare_api_token" {
  metadata {
    name      = "wildcard-pw-az-demo-tls"
    namespace = "cert-manager"
  }

  data = {
    "api-token" = var.api_token
  }

  type = "Opaque"

  depends_on = [helm_release.cert_manager]
}

resource "kubernetes_secret_v1" "monitoring_tls_secret" {
  metadata {
    name      = "wildcard-pw-az-demo-tls"
    namespace = "monitoring"
  }

  data = {
    "api-token" = var.api_token
  }

  type = "Opaque"

  depends_on = [helm_release.cert_manager, helm_release.prometheus]
}

resource "kubernetes_secret_v1" "ingress_nginx_token" {
  metadata {
    name      = "wildcard-pw-az-demo-tls"
    namespace = "ingress-nginx"
  }

  data = {
    "api-token" = var.api_token
  }

  type = "Opaque"

  depends_on = [helm_release.cert_manager]
}

# resource "kubernetes_manifest" "letsencrypt_dns01" {
#   manifest = {
#     "apiVersion" = "cert-manager.io/v1"
#     "kind"       = "ClusterIssuer"
#     "metadata" = {
#       "name" = "letsencrypt-dns01"
#     }
#     "spec" = {
#       "acme" = {
#         "server" = "https://acme-v02.api.letsencrypt.org/directory"
#         "email"  = "pacwilliams@hotmail.com"
#         "privateKeySecretRef" = {
#           "name" = "letsencrypt-dns01-account-key"
#         }
#         "solvers" = [
#           {
#             "dns01" = {
#               "cloudflare" = {
#                 "email" = "pacwilliams@hotmail.com"
#                 "apiTokenSecretRef" = {
#                   "name" = "wildcard-pw-az-demo-tls"
#                   "key"  = "api-token"
#                 }
#               }
#             }
#           }
#         ]
#       }
#     }
#   }

#   depends_on = [helm_release.cert_manager, azurerm_kubernetes_cluster.aks_cluster]
# }

resource "azurerm_role_assignment" "aks_network_contrib" {
  principal_id         = azurerm_kubernetes_cluster.aks_cluster.identity[0].principal_id
  role_definition_name = "Network Contributor"
  scope                = azurerm_resource_group.rg.id
}


resource "azurerm_key_vault_secret" "aks_kubeconfig" {
  name         = "aks-kubeconfig"
  value        = azurerm_kubernetes_cluster.aks_cluster.kube_config_raw
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [azurerm_key_vault.kv, azurerm_role_assignment.sp_kv_secrets_user, azurerm_role_assignment.kv_sp_assignment]
}

resource "azurerm_role_assignment" "aks_role" {
  principal_id                     = azurerm_kubernetes_cluster.aks_cluster.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "law" {
  name                = "odl1986716-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "aks_diagnostics" {
  name                       = "aks-diagnostics"
  target_resource_id         = azurerm_kubernetes_cluster.aks_cluster.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  # Enable AKS audit logs
  enabled_log {
    category = "kube-audit"
  }

  # Enable AKS audit admin logs
  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "kube-apiserver"
  }
  enabled_log {
    category = "kube-scheduler"
  }
  enabled_log {
    category = "guard"
  }

  enabled_log {
    category = "cluster-autoscaler"
  }


  enabled_log {
    category = "cloud-controller-manager"
  }
  # You can also send metrics if needed
  enabled_metric {
    category = "AllMetrics"

  }
}

# Prometheus Helm release
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "monitoring"

  create_namespace = true

  values = [
    <<EOF
alertmanager:
  enabled: true

server:
  service:
    type: LoadBalancer

kube-state-metrics:
  enabled: true

nodeExporter:
  enabled: true
EOF
  ]
}

# Grafana Helm release
resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = "monitoring"
  values = [
    <<EOF
adminUser: "admin"
adminPassword: "${random_password.grafana_pwd.result}"
service:
  type: ClusterIP
ingress:
  enabled: true
  ingressClassName: nginx
  hosts:
    - grafana.pw-az-demo.com
  tls:
    - hosts:
        - grafana.pw-az-demo.com
      secretName: wildcard-pw-az-demo-tls

EOF
  ]

  depends_on = [helm_release.prometheus]
}

resource "kubernetes_manifest" "grafana_cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "grafana-cert"
      namespace = "monitoring"
    }
    spec = {
      secretName = "wildcard-pw-az-demo-tls"
      issuerRef = {
        name = "letsencrypt-dns01"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        "grafana.pw-az-demo.com"
      ]
    }
  }

  depends_on = [
    helm_release.cert_manager,
    kubernetes_manifest.letsencrypt_dns01,
    helm_release.grafana
  ]
}

resource "grafana_data_source" "prometheus" {
  name        = "Prometheus"
  type        = "prometheus"
  provider    = grafana.main
  url         = "http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090"
  access_mode = "proxy"

  json_data_encoded = jsonencode({
    httpMethod = "POST"
  })

  depends_on = [helm_release.grafana, helm_release.nginx_ingress, kubernetes_manifest.grafana_cert]
}

resource "grafana_dashboard" "k8s" {
  provider    = grafana.main
  config_json = file("${path.module}/dashboards/6417_rev1.json")

  depends_on = [helm_release.grafana, data.kubernetes_service_v1.grafana, grafana_data_source.prometheus]
}

resource "grafana_dashboard" "k8s2" {
  provider    = grafana.main
  config_json = file("${path.module}/dashboards/6663_rev1.json")

  depends_on = [helm_release.grafana, data.kubernetes_service_v1.grafana, grafana_dashboard.k8s]
}

resource "grafana_dashboard" "k8s3" {
  provider    = grafana.main
  config_json = file("${path.module}/dashboards/15758_rev44.json")

  depends_on = [helm_release.grafana, data.kubernetes_service_v1.grafana, grafana_dashboard.k8s]
}

resource "grafana_dashboard" "k8s4" {
  provider    = grafana.main
  config_json = file("${path.module}/dashboards/15759_rev40.json")

  depends_on = [helm_release.grafana, data.kubernetes_service_v1.grafana, grafana_dashboard.k8s]
}

resource "grafana_dashboard" "k8s5" {
  provider    = grafana.main
  config_json = file("${path.module}/dashboards/15761_rev20.json")

  depends_on = [helm_release.grafana, data.kubernetes_service_v1.grafana, grafana_dashboard.k8s]
}

data "kubernetes_service_v1" "grafana" {
  metadata {
    name      = helm_release.grafana.name
    namespace = helm_release.grafana.namespace
  }
}


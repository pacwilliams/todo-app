terraform {
  cloud {

    organization = "Wiz_Exercise"

    workspaces {
      name = "wiz-exercise"
    }
  }
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~>2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.1.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.0.0"
    }

    grafana = {
      source  = "grafana/grafana"
      version = "~>4.21.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks_cluster.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config[0].cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "az"
    args        = [
      "aks", "get-credentials",
      "--resource-group", azurerm_kubernetes_cluster.aks_cluster.resource_group_name,
      "--name", azurerm_kubernetes_cluster.aks_cluster.name,
      "--overwrite-existing"
    ]
  }

}

provider "helm" {
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.aks_cluster.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config[0].cluster_ca_certificate)
  }
}

provider "grafana" {
  alias = "main"
    url = "http://${coalesce(
    data.kubernetes_service_v1.grafana.status[0].load_balancer[0].ingress[0].ip,
    data.kubernetes_service_v1.grafana.status[0].load_balancer[0].ingress[0].hostname
  )}:3000"
  auth = "admin:${random_password.grafana_pwd.result}"
}


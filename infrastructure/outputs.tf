output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.aks_cluster.name
}

output "virtual_network_name" {
  description = "The name of the created virtual network."
  value       = azurerm_virtual_network.my_terraform_network.name
}

output "public_ip_address" {
  value = azurerm_linux_virtual_machine.my_terraform_vm.public_ip_address
}

output "aks_ingress_public_ip" {
  value = azurerm_public_ip.aks_ingress_ip.ip_address
}

output "aks_ingress_public_fqdn" {
  value = azurerm_public_ip.aks_ingress_ip.fqdn
}

output "aks_ingress_custom_domain" {
  value = azurerm_dns_a_record.aks_dns.fqdn
}

output "grafana_lb_ip" {
  value = data.kubernetes_service_v1.grafana.status[0].load_balancer[0].ingress[0].ip
}

output "grafana_lb_hostname" {
  value = data.kubernetes_service_v1.grafana.status[0].load_balancer[0].ingress[0].hostname
}

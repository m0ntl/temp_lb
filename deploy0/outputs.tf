output "consumer_subnet_id" {
  value = azurerm_subnet.consumer_subnet.id
}

output "bap_id" {
  value = var.deploy_vnet_subnets_only ? "" : var.use_lb ? azurerm_lb_backend_address_pool.lb[0].id : azurerm_application_gateway.agw[0].backend_address_pool[*].id
}

output "health_probe_id" {
  value = local.deploy_lb ? azurerm_lb_probe.lb[0].id : null
}

output "lb_id" {
  value = local.deploy_lb ? azurerm_lb.lb[0].id : ""
}

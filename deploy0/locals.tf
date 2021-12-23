locals {
  backend_address_pool_name      = "${azurerm_virtual_network.myvnet.name}-beap"
  frontend_port_name             = "${azurerm_virtual_network.myvnet.name}-feport"
  frontend_ip_configuration_name = "${azurerm_virtual_network.myvnet.name}-feip"
  http_setting_name              = "${azurerm_virtual_network.myvnet.name}-be-htst"
  listener_name                  = "${azurerm_virtual_network.myvnet.name}-httplstn"
  request_routing_rule_name      = "${azurerm_virtual_network.myvnet.name}-rqrt"
  redirect_configuration_name    = "${azurerm_virtual_network.myvnet.name}-rdrcfg"

  gateway_name       = "my-appgateway"
  load_balancer_name = "my-lb"

  lb_probe_name = "http_probe"

  deploy_lb                = var.use_lb && !var.deploy_vnet_subnets_only
  deploy_agw               = !var.use_lb && !var.deploy_vnet_subnets_only
  deploy_bastion           = !var.deploy_vnet_subnets_only && var.deploy_test_infrastructure
  deploy_management_server = !var.deploy_vnet_subnets_only && var.deploy_test_infrastructure
}

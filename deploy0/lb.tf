resource "azurerm_lb" "lb" {
  count               = local.deploy_lb ? 1 : 0
  name                = local.load_balancer_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  sku      = "Standard"
  sku_tier = "Regional"

  frontend_ip_configuration {
    name              = local.frontend_ip_configuration_name
    availability_zone = "Zone-Redundant"
    subnet_id         = azurerm_subnet.agwlb_subnet.id
  }
}

resource "azurerm_lb_backend_address_pool" "lb" {
  count           = local.deploy_lb ? 1 : 0
  loadbalancer_id = azurerm_lb.lb[0].id
  name            = local.backend_address_pool_name
}


resource "azurerm_lb_probe" "lb" {
  count               = local.deploy_lb ? 1 : 0
  resource_group_name = azurerm_resource_group.rg.name


  name                = local.lb_probe_name
  loadbalancer_id     = azurerm_lb.lb[0].id
  port                = 80
  protocol            = "Http"
  request_path        = "/"
  interval_in_seconds = 5

}

resource "azurerm_lb_rule" "lb" {
  count                          = local.deploy_lb ? 1 : 0
  resource_group_name            = azurerm_resource_group.rg.name
  loadbalancer_id                = azurerm_lb.lb[0].id
  name                           = local.request_routing_rule_name
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = local.frontend_ip_configuration_name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.lb[0].id]
  probe_id                       = azurerm_lb_probe.lb[0].id
}

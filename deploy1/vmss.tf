resource "azurerm_linux_virtual_machine_scale_set" "ss" {
  name                = "ss1-vmss"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard_DS2_v2"
  instances           = 1
  admin_username      = "adminuser"

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/forter_id.pub")
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  custom_data = base64encode(file("${path.module}/custom_data.yml"))

  upgrade_mode = var.apply_bap_approach ? "Rolling" : "Manual"

  dynamic "rolling_upgrade_policy" {
    for_each = var.apply_bap_approach ? [1] : [] # { for v in [1] : v => v if var.apply_bap_approach } # 
    content {
      max_batch_instance_percent              = 50
      max_unhealthy_instance_percent          = 75
      max_unhealthy_upgraded_instance_percent = 50
      pause_time_between_batches              = "PT1M"
    }
  }

  health_probe_id = var.apply_bap_approach ? var.health_probe_id : null

  network_interface {
    name                      = "primary"
    primary                   = true
    network_security_group_id = azurerm_network_security_group.ss_nic_nsg.id

    ip_configuration {
      name                                         = "primary"
      primary                                      = true
      subnet_id                                    = var.subnet_id
      application_gateway_backend_address_pool_ids = var.apply_bap_approach && !var.use_lb ? [var.bap_id] : null
      load_balancer_backend_address_pool_ids       = var.apply_bap_approach && var.use_lb ? [var.bap_id] : null
    }
  }
}

resource "azurerm_network_security_group" "ss_nic_nsg" {
  name                = "ss1-vmss-nsg"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  security_rule {
    name                       = "lb-probe-access" # used by python code
    priority                   = 500
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
  lifecycle {
    ignore_changes = [
      security_rule
    ]
  }
}

# resource "azurerm_network_security_rule" "ss_nic_nsg_rule" { # see https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-custom-probe-overview
#   name                         = "lb-probe-access"
#   priority                     = 500
#   direction                    = "Inbound"
#   access                       = "Deny"
#   protocol                     = "Tcp"
#   source_port_range            = "*"
#   destination_port_range       = "*"
#   source_address_prefix        = "AzureLoadBalancer"
#   destination_address_prefixes = ["*"]
#   resource_group_name          = azurerm_resource_group.rg.name
#   network_security_group_name  = azurerm_network_security_group.ss_nic_nsg.name

#   lifecycle {
#     ignore_changes = [
#       access
#     ]
#   }
# }



module "label" {
  source = "github.com/robc-io/terraform-null-label.git?ref=0.16.1"
  tags = {
    NetworkName = var.network_name
    Owner       = var.owner
    Terraform   = true
    VpcType     = "main"
  }

  environment = var.environment
  namespace   = var.namespace
  stage       = var.stage
}

data azurerm_resource_group "this" {
  name = var.azure_resource_group_name
}

resource "azurerm_public_ip" "this" {
  count               = var.use_external_lb ? 1 : 0
  name                = "api-lb-pub-ip"
  location            = var.region
  resource_group_name = data.azurerm_resource_group.this.name
  allocation_method   = "Static"
}

resource "azurerm_lb" "public" {
  count               = var.use_external_lb ? 1 : 0
  name                = "api-lb"
  location            = var.region
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = module.label.tags

  frontend_ip_configuration {
    name                 = "api-lb-pub-ip"
    public_ip_address_id = azurerm_public_ip.this[0].id
  }
}

resource "azurerm_lb" "private" {
  count               = var.use_external_lb ? 0 : 1
  name                = "api-lb"
  location            = var.region
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = module.label.tags

  frontend_ip_configuration {
    name                          = "api-lb-pub-ip"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_lb_backend_address_pool" "this" {
  loadbalancer_id     = var.use_external_lb ? azurerm_lb.public[0].id : azurerm_lb.private[0].id
  name                = "BackendAddressPool"
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_lb_probe" "node-synced" {
  loadbalancer_id     = var.use_external_lb ? azurerm_lb.public[0].id : azurerm_lb.private[0].id
  name                = "node-sync-hc"
  port                = 5500
  protocol            = "Http"
  request_path        = "/"
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_lb_rule" "substrate-rpc" {
  name            = "substrateRPC"
  loadbalancer_id = var.use_external_lb ? azurerm_lb.public[0].id : azurerm_lb.private[0].id

  frontend_ip_configuration_name = "api-lb-pub-ip"
  frontend_port                  = 9933

  backend_address_pool_id = azurerm_lb_backend_address_pool.this.id
  backend_port            = 9933
  probe_id                = azurerm_lb_probe.node-synced.id

  load_distribution   = "SourceIPProtocol"
  protocol            = "Tcp"
  resource_group_name = data.azurerm_resource_group.this.name
}

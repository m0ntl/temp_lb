variable "use_lb" {
  type        = bool
  description = "if true then use Azure LB. If false then use Application Gateway"
  default     = true
}

variable "deploy_vnet_subnets_only" {
  type        = bool
  description = "If true then only VNET and subnets are deployed. This is useful for testing backend servers without paying for a LB"
  default     = false
}

variable "deploy_test_infrastructure" {
  type    = bool
  default = true
}

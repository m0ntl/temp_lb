variable "subnet_id" {
  type        = string
  description = "Which subnet should the VMSS be deployed to"
}

variable "bap_id" {
  type        = string
  default     = ""
  description = "Which BAP should this VMSS be associated with. This must be set if var.apply_bap_approach is 'true'"
}

variable "health_probe_id" {
  type        = string
  default     = ""
  description = "Which health probe should this VMSS be associated with. This must be set if var.apply_bap_approach is 'true'"
}

variable "apply_bap_approach" {
  type        = bool
  default     = false
  description = "If true then associate VMSS with a BAP"
}

variable "use_lb" {
  type        = bool
  description = "if true then BAP is linked to Azure LB, if false then it is linked to an Application Gateway"
  default     = true
}

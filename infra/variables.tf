variable "subscription_id" {
  description = "Azure subscription to deploy into."
  type        = string
}

variable "project" {
  description = "Project name used in resource names and tags."
  type        = string
  default     = "web-app"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "westeurope"
}

variable "sku_tier" {
  description = "Static Web App SKU tier (Free or Standard)."
  type        = string
  default     = "Free"
}

variable "tags" {
  description = "Extra tags merged onto the default tags."
  type        = map(string)
  default     = {}
}

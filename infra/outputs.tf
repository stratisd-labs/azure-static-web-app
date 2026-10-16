output "default_hostname" {
  description = "Default hostname of the Static Web App."
  value       = azurerm_static_web_app.main.default_host_name
}

output "deployment_token" {
  description = "API key used by the SWA CLI to deploy."
  value       = azurerm_static_web_app.main.api_key
  sensitive   = true
}

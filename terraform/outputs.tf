output "resource_group_name" {
  description = "Nom du Resource Group"
  value       = azurerm_resource_group.main.name
}

output "acr_login_server" {
  description = "URL de connexion à l'Azure Container Registry"
  value       = azurerm_container_registry.acr.login_server
}

output "app_service_url" {
  description = "URL publique de l'App Service (HTTPS)"
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "app_service_name" {
  description = "Nom de l'App Service (pour azure-pipelines.yml)"
  value       = azurerm_linux_web_app.main.name
}

output "staging_slot_url" {
  description = "URL du slot staging"
  value       = "https://${azurerm_linux_web_app_slot.staging.default_hostname}"
}

output "app_insights_connection_string" {
  description = "Chaîne de connexion Application Insights (sensible)"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "key_vault_uri" {
  description = "URI du Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "mysql_fqdn" {
  description = "FQDN du serveur MySQL Flexible"
  value       = azurerm_mysql_flexible_server.main.fqdn
}

output "app_service_principal_id" {
  description = "Object ID de la Managed Identity de l'App Service"
  value       = azurerm_linux_web_app.main.identity[0].principal_id
}

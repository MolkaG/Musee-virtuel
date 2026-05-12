# ═══════════════════════════════════════════════════════════════════════════════
# Musée Virtuel — Infrastructure Azure
# ═══════════════════════════════════════════════════════════════════════════════

# ── Locaux : noms normalisés ───────────────────────────────────────────────────
locals {
  name_prefix  = "${var.prefix}-${var.env}"
  acr_name     = "${var.prefix}acr${var.env}"                  # alphanumeric only
  kv_name      = "kv-${substr(var.prefix, 0, 10)}-${var.env}" # max 24 chars
  app_name     = "app-${local.name_prefix}"
  tags = {
    project     = "musee-virtuel"
    environment = var.env
    managed_by  = "terraform"
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Resource Group
# ═══════════════════════════════════════════════════════════════════════════════
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

# ═══════════════════════════════════════════════════════════════════════════════
# Azure Container Registry
# ═══════════════════════════════════════════════════════════════════════════════
resource "azurerm_container_registry" "acr" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku
  admin_enabled       = false # Managed Identity remplace le compte admin
  tags                = local.tags
}

# ═══════════════════════════════════════════════════════════════════════════════
# Observabilité : Log Analytics + Application Insights
# ═══════════════════════════════════════════════════════════════════════════════
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_application_insights" "main" {
  name                = "ai-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = local.tags
}

# ═══════════════════════════════════════════════════════════════════════════════
# Key Vault + Secrets
# ═══════════════════════════════════════════════════════════════════════════════
resource "azurerm_key_vault" "main" {
  name                       = local.kv_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags                       = local.tags
}

# Accès pour le déployeur (compte CLI / Service Principal Terraform)
resource "azurerm_key_vault_access_policy" "deployer" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
}

# Mot de passe MySQL généré aléatoirement
resource "random_password" "mysql" {
  length           = 20
  special          = true
  override_special = "!#%&*-_=+?"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "azurerm_key_vault_secret" "mysql_password" {
  name         = "mysql-admin-password"
  value        = random_password.mysql.result
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_key_vault_access_policy.deployer]

  tags = local.tags
}

resource "azurerm_key_vault_secret" "app_insights_connection" {
  name         = "appinsights-connection-string"
  value        = azurerm_application_insights.main.connection_string
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_key_vault_access_policy.deployer]

  tags = local.tags
}

# ═══════════════════════════════════════════════════════════════════════════════
# Azure Database for MySQL Flexible Server
# ═══════════════════════════════════════════════════════════════════════════════
resource "azurerm_mysql_flexible_server" "main" {
  name                   = "mysql-${local.name_prefix}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  administrator_login    = var.mysql_admin_username
  administrator_password = random_password.mysql.result
  sku_name               = "B_Standard_B1ms"
  version                = "8.0.21"
  zone                   = "1"
  backup_retention_days  = 7
  tags                   = local.tags
}

resource "azurerm_mysql_flexible_database" "main" {
  name                = "chatdb"
  resource_group_name = azurerm_resource_group.main.name
  server_name         = azurerm_mysql_flexible_server.main.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

# Règle firewall : autoriser les App Services Azure
resource "azurerm_mysql_flexible_server_firewall_rule" "azure_services" {
  name                = "allow-azure-services"
  resource_group_name = azurerm_resource_group.main.name
  server_name         = azurerm_mysql_flexible_server.main.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

# ═══════════════════════════════════════════════════════════════════════════════
# App Service Plan + Web App (Container Linux)
# ═══════════════════════════════════════════════════════════════════════════════
resource "azurerm_service_plan" "main" {
  name                = "asp-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.app_service_sku # P1v2 requis pour les slots staging
  tags                = local.tags
}

resource "azurerm_linux_web_app" "main" {
  name                = local.app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true
  tags                = local.tags

  # Managed Identity système pour accès ACR + Key Vault
  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on          = true
    websockets_enabled = true # Requis pour Spring WebSocket / STOMP

    application_stack {
      docker_image_name        = "${local.acr_name}.azurecr.io/${local.name_prefix}:${var.image_tag}"
      docker_registry_url      = "https://${local.acr_name}.azurecr.io"
      docker_registry_username = ""
      docker_registry_password = ""
    }
  }

  app_settings = {
    # Port exposé par le container Spring Boot
    "WEBSITES_PORT" = "8090"

    # Application Insights via Key Vault (Managed Identity)
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.app_insights_connection.id})"

    # ACR via Managed Identity (pas de mot de passe)
    "DOCKER_REGISTRY_SERVER_URL"      = "https://${azurerm_container_registry.acr.login_server}"
    "DOCKER_ENABLE_CI"                = "true"

    # MySQL connection (mot de passe via Key Vault)
    "SPRING_DATASOURCE_URL"           = "jdbc:mysql://${azurerm_mysql_flexible_server.main.fqdn}:3306/chatdb?useSSL=true&serverTimezone=UTC"
    "SPRING_DATASOURCE_USERNAME"      = var.mysql_admin_username
    "SPRING_DATASOURCE_PASSWORD"      = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.mysql_password.id})"
  }

  logs {
    http_logs {
      retention_in_days = 7
    }
    application_logs {
      file_system_level = "Information"
    }
  }
}

# Slot staging pour Blue/Green deployment
resource "azurerm_linux_web_app_slot" "staging" {
  name           = "staging"
  app_service_id = azurerm_linux_web_app.main.id
  https_only     = true
  tags           = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on          = false # économie sur slot staging
    websockets_enabled = true

    application_stack {
      docker_image_name        = "${local.acr_name}.azurecr.io/${local.name_prefix}:${var.image_tag}"
      docker_registry_url      = "https://${local.acr_name}.azurecr.io"
      docker_registry_username = ""
      docker_registry_password = ""
    }
  }

  app_settings = {
    "WEBSITES_PORT"              = "8090"
    "DOCKER_REGISTRY_SERVER_URL" = "https://${azurerm_container_registry.acr.login_server}"
    "DOCKER_ENABLE_CI"           = "true"
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# RBAC : Managed Identity → ACR (AcrPull) + Key Vault
# ═══════════════════════════════════════════════════════════════════════════════

# App Service prod → AcrPull
resource "azurerm_role_assignment" "app_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# Slot staging → AcrPull
resource "azurerm_role_assignment" "staging_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging.identity[0].principal_id
}

# App Service → Key Vault (lecture des secrets uniquement)
resource "azurerm_key_vault_access_policy" "app_service" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = azurerm_linux_web_app.main.identity[0].tenant_id
  object_id    = azurerm_linux_web_app.main.identity[0].principal_id

  secret_permissions = ["Get"]
}

# ═══════════════════════════════════════════════════════════════════════════════
# Azure Monitor — Alertes
# ═══════════════════════════════════════════════════════════════════════════════
resource "azurerm_monitor_action_group" "main" {
  name                = "ag-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "musee-alert"
  tags                = local.tags

  email_receiver {
    name                    = "admin-email"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

# Alerte 1 : erreurs HTTP 5xx > 5 en 5 minutes
resource "azurerm_monitor_metric_alert" "http5xx" {
  name                = "alert-http5xx-${var.env}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_web_app.main.id]
  description         = "Trop d'erreurs HTTP 5xx détectées"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}

# Alerte 2 : CPU > 80% en moyenne sur 5 minutes
resource "azurerm_monitor_metric_alert" "cpu_high" {
  name                = "alert-cpu-high-${var.env}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_web_app.main.id]
  description         = "Utilisation CPU élevée (> 80%)"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}

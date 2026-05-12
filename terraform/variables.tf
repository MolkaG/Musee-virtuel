variable "prefix" {
  description = "Préfixe utilisé pour nommer toutes les ressources Azure"
  type        = string
  default     = "museevirtuel"

  validation {
    condition     = length(var.prefix) <= 14 && can(regex("^[a-z0-9]+$", var.prefix))
    error_message = "Le préfixe doit être en minuscules alphanumériques, max 14 caractères."
  }
}

variable "env" {
  description = "Environnement cible : dev ou prod"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "L'environnement doit être 'dev' ou 'prod'."
  }
}

variable "location" {
  description = "Région Azure (ex: westeurope, francecentral)"
  type        = string
  default     = "westeurope"
}

variable "mysql_admin_username" {
  description = "Login administrateur MySQL"
  type        = string
  default     = "mysqladmin"
}

variable "alert_email" {
  description = "Email destinataire des alertes Azure Monitor"
  type        = string
}

variable "image_tag" {
  description = "Tag de l'image Docker à déployer (ex: latest, 42)"
  type        = string
  default     = "latest"
}

variable "acr_sku" {
  description = "SKU de l'Azure Container Registry"
  type        = string
  default     = "Standard"
}

variable "app_service_sku" {
  description = "SKU de l'App Service Plan (P1v2 minimum pour les slots)"
  type        = string
  default     = "P1v2"
}

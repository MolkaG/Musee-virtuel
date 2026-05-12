# ─── Valeurs pour l'environnement DEV ────────────────────────────────────────
# Usage : terraform plan -var-file="dev.tfvars"

prefix          = "museevirtuel"
env             = "dev"
location        = "westeurope"
mysql_admin_username = "mysqladmin"
alert_email     = "molka.gmarr@gmail.com"
image_tag       = "latest"
acr_sku         = "Standard"
app_service_sku = "P1v2"

# Note : mysql_admin_password est généré automatiquement par random_password
# et stocké dans Key Vault — ne jamais le mettre ici

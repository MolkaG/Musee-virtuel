# Guide de déploiement — Musée Virtuel (WebSocketsChat)

Ce guide permet de reproduire l'environnement complet depuis zéro.

---

## Prérequis

| Outil | Version | Vérification |
|---|---|---|
| Azure CLI | ≥ 2.50 | `az --version` |
| Terraform | ≥ 1.5 | `terraform --version` |
| Docker | ≥ 24 | `docker --version` |
| Java | 17 | `java -version` |
| Maven | ≥ 3.8 | `mvn --version` |
| Git | ≥ 2.40 | `git --version` |

---

## Étape 1 — Connexion Azure

```bash
az login
az account list --output table
az account set --subscription "<VOTRE_SUBSCRIPTION_ID>"
```

---

## Étape 2 — Créer le backend Terraform (Storage Account)

```bash
# Variables
RG_TFSTATE="rg-tfstate"
SA_NAME="tfstatemuseevirtuel"   # Adapter si le nom est pris (unique global)
LOCATION="westeurope"

# Créer le resource group pour le state
az group create --name $RG_TFSTATE --location $LOCATION

# Créer le storage account
az storage account create \
  --name $SA_NAME \
  --resource-group $RG_TFSTATE \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2

# Créer le container blob
az storage container create \
  --name tfstate \
  --account-name $SA_NAME
```

---

## Étape 3 — Déployer l'infrastructure Terraform

```bash
cd terraform/

# Initialiser avec le backend distant
terraform init

# Vérifier le plan
terraform plan -var-file="dev.tfvars" -out=plan.tfplan

# Appliquer (~ 10-15 minutes)
terraform apply plan.tfplan
```

> Terraform crée : Resource Group, ACR, App Service Plan, App Service + slot staging,  
> MySQL Flexible Server, Application Insights, Log Analytics, Key Vault + secrets, alertes Azure Monitor.

---

## Étape 4 — Créer le repo sur Azure DevOps

```bash
# Connexion Azure DevOps (si pas déjà fait)
az devops configure --defaults organization=https://dev.azure.com/<VOTRE_ORG>

# Créer le projet
az devops project create --name "musee-virtuel" --visibility private

# Récupérer l'URL du repo Azure
az repos list --project "musee-virtuel" --output table
```

Migrer le code vers Azure Repos :

```bash
cd /home/testauto/Musee-virtuel

git remote add azure <URL_AZURE_REPO>
git push azure main
git push azure develop
```

---

## Étape 5 — Service Connections Azure DevOps

Créer 3 service connections dans **Project Settings → Service Connections** :

### 5.1 — Azure Service Connection
- Type : **Azure Resource Manager**
- Auth : Service Principal (automatic)
- Subscription : votre subscription
- Nom : `Azure-Service-Connection`
- Cocher : "Grant access to all pipelines"

### 5.2 — ACR Service Connection
- Type : **Docker Registry**
- Registry type : Azure Container Registry
- Subscription : votre subscription
- ACR : `museevirtuelacr<env>`
- Nom : `ACR-Service-Connection`

### 5.3 — SonarCloud Service Connection
- Type : **SonarCloud**
- Token : généré sur https://sonarcloud.io → My Account → Security
- Nom : `SonarCloud-Connection`

---

## Étape 6 — Configurer SonarCloud

1. Aller sur https://sonarcloud.io → **+** → Analyze new project
2. Choisir le repo GitHub ou Azure DevOps
3. Récupérer le **Project Key** et l'**Organization Key**
4. Dans Azure DevOps Library, créer le groupe `musee-virtuel-variables` avec :

| Variable | Valeur | Secret ? |
|---|---|---|
| `ACR_LOGIN_SERVER` | `museevirtuelacr<env>.azurecr.io` | Non |
| `APP_NAME_DEV` | output Terraform `app_service_name` | Non |
| `APP_NAME_PROD` | output Terraform `app_service_name` (prod) | Non |
| `RESOURCE_GROUP` | `rg-musee-virtuel-prod` | Non |
| `SONAR_ORG` | votre org SonarCloud | Non |
| `SONAR_PROJECT_KEY` | votre project key SonarCloud | Non |

---

## Étape 7 — Configurer les environnements DevOps

Dans **Pipelines → Environments** :

**Environnement `dev`** : pas d'approbation (déploiement automatique)

**Environnement `prod`** :
1. Créer l'environnement `prod`
2. Cliquer "Approvals and checks" → + → Approvals
3. Ajouter votre compte comme approbateur
4. Timeout : 24h

---

## Étape 8 — Premier déploiement

```bash
# S'assurer d'être sur la bonne branche
git checkout develop

# Tester le build local
cd WebSocketsChatProjet-main
mvn clean package -DskipTests

# Test Docker local
cd ..
docker compose up --build

# Push pour déclencher le pipeline
git add .
git commit -m "feat: initial DevOps setup"
git push azure develop    # → déclenche Build + DockerBuild + DeployDev

# Pour déclencher PROD :
git checkout main
git merge develop
git push azure main       # → attend approbation manuelle
```

---

## Vérifications post-déploiement

```bash
# URL de l'app (depuis terraform output)
terraform output app_service_url

# Vérifier Application Insights
az monitor app-insights component show \
  --app ai-museevirtuel-dev \
  --resource-group rg-musee-virtuel-dev

# Vérifier les secrets dans Key Vault
az keyvault secret list --vault-name kv-museevirtuel-dev

# Logs de l'App Service
az webapp log tail \
  --name app-museevirtuel-dev \
  --resource-group rg-musee-virtuel-dev
```

---

## Pièges courants et solutions

| Problème | Cause | Solution |
|---|---|---|
| `Error: ACR name already taken` | Nom global unique | Changer `prefix` dans `dev.tfvars` |
| `403 Forbidden` sur ACR | Managed Identity pas propagée | Attendre 2-3 min après `terraform apply` |
| Key Vault soft-delete conflict | Vault existant en soft-delete | `az keyvault purge --name kv-xxx` |
| Pipeline bloqué sur SonarCloud | Token expiré | Régénérer token sur sonarcloud.io |
| App Service répond 503 | Image non trouvée / AcrPull manquant | Vérifier `az role assignment list` |
| WebSocket connexion refusée | Option désactivée sur App Service | `az webapp config set --web-sockets-enabled true` |
| MySQL connexion refusée | Règle firewall manquante | Vérifier `azurerm_mysql_flexible_server_firewall_rule` |
| Slot swap échoue | SKU Basic (pas de slots) | Utiliser au minimum P1v2 |
| `terraform init` échoue | Backend Storage inexistant | Exécuter l'Étape 2 d'abord |

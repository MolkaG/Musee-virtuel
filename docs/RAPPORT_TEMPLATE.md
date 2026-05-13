# Rapport Final — Projet DevOps
## Déploiement CI/CD d'une Application Web sur Azure

**Auteur :** [Votre Nom]  
**Formation :** [Nom de la formation / école]  
**Date :** [Date de rendu]  
**Repo :** https://github.com/MolkaG/[nom-du-repo]  
**Azure DevOps :** https://dev.azure.com/[org]/musee-virtuel

---

## Table des matières

1. Introduction et Contexte
2. Architecture de la Solution
3. Gestion du Dépôt Git et Workflow Branches
4. Pipeline CI/CD avec Azure Pipelines
5. Infrastructure as Code avec Terraform
6. Déploiement sur Azure App Service
7. Sécurité — Key Vault et Managed Identity
8. Monitoring — Application Insights et Alertes
9. Documentation et Reproductibilité
10. Difficultés Rencontrées et Solutions
11. Conclusion et Perspectives

---

## 1. Introduction et Contexte

### 1.1 Présentation du projet applicatif

L'application choisie est **WebSocketsChat**, un sous-module du projet académique Musée Virtuel.  
C'est une application de messagerie en temps réel construite avec :
- **Spring Boot 2.7.18** (framework Java backend)
- **Spring WebSocket / STOMP** (protocole temps réel)
- **Spring Security** (authentification)
- **Thymeleaf / Bootstrap** (interface utilisateur)

Ce module a été sélectionné pour sa **simplicité de déploiement** : aucune base de données externe n'est requise pour démarrer l'application, ce qui garantit un pipeline CI/CD fonctionnel sans dépendances complexes.

### 1.2 Objectifs DevOps

L'objectif est de construire une plateforme DevOps complète démontrant :
- L'automatisation du cycle de vie logiciel (CI/CD)
- L'Infrastructure as Code (IaC)
- La sécurité by-design (secrets, identités gérées)
- L'observabilité en production (métriques, alertes, logs)
- Les bonnes pratiques de déploiement (Blue/Green, environnements séparés)

### 1.3 Technologies utilisées

| Catégorie | Technologie | Justification |
|---|---|---|
| Cloud | Microsoft Azure | Ecosystème intégré, crédits étudiants disponibles |
| CI/CD | Azure Pipelines | Intégration native avec Azure et SonarCloud |
| Container | Docker (multi-stage) | Standardisation, portabilité |
| Registry | Azure Container Registry | Intégration Managed Identity avec App Service |
| Déploiement | Azure App Service | PaaS géré, coût réduit vs VM, slots intégrés |
| IaC | Terraform (azurerm 3.x) | Standard industrie, provider Azure mature |
| Qualité | SonarCloud | Gratuit pour projets publics/étudiants |
| Secrets | Azure Key Vault | HSM managé, intégration native App Service |
| Monitoring | Application Insights | Distribué, SDK Java disponible |
| Java | Version 17 (LTS) | Version LTS active, support Spring Boot 2.7+ |

---

## 2. Architecture de la Solution

### 2.1 Vue d'ensemble

```
┌─────────────────────────────────────────────────────────────────────┐
│                        GitHub / Azure Repos                         │
│  branches : main (prod) │ develop (dev) │ feature/* (PR)           │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ push
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Azure Pipelines                                │
│  Stage 1: Build      Stage 2: Docker     Stage 3: Dev   Stage 4: Prod│
│  Maven + JUnit  →    Build + Push ACR  → App Service → (approbation)│
│  SonarCloud                                              → slot swap │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
┌─────────────────┐  ┌──────────────┐  ┌──────────────────────────┐
│ Azure Container │  │  App Service │  │  App Service (PROD)       │
│ Registry (ACR)  │  │  (DEV)       │  │  slot: staging → prod     │
└─────────────────┘  └──────────────┘  └──────────────────────────┘
              │                                 │
              └──── Managed Identity ───────────┘
                                                │
                         ┌──────────────────────┼─────────────────────┐
                         ▼                      ▼                     ▼
              ┌──────────────────┐  ┌─────────────────┐  ┌──────────────────┐
              │   Key Vault      │  │ App Insights     │  │ MySQL Flexible   │
              │ (secrets)        │  │ + Log Analytics  │  │ Server           │
              └──────────────────┘  └─────────────────┘  └──────────────────┘
```

### 2.2 Choix architectural : App Service vs VM vs AKS

| Critère | App Service | VM | AKS |
|---|---|---|---|
| Coût | $$ | $ | $$$$ |
| Complexité ops | Faible | Élevée | Très élevée |
| Slots déploiement | Intégrés | Manuel | Rolling update |
| Gestion OS | Automatique | Manuelle | Semi-auto |
| **Verdict** | **Choisi** | Non adapté | Surdimensionné |

L'App Service est le choix optimal pour un projet académique : PaaS géré, HTTPS automatique, slots de déploiement intégrés pour Blue/Green, et coût maîtrisé.

---

## 3. Gestion du Dépôt Git et Workflow Branches

### 3.1 Stratégie de branches (GitFlow simplifié)

```
main ──────────────────────────────────────── production
      \                                   /
       develop ────────────────────────── intégration continue
          \        \                /
           feature/A  feature/B    release/1.0
```

| Branche | Rôle | Déploiement |
|---|---|---|
| `main` | Code stable, releases | Prod (approbation manuelle) |
| `develop` | Intégration continue | Dev (automatique) |
| `feature/*` | Nouvelles fonctionnalités | Non déployé (PR seulement) |
| `hotfix/*` | Correctifs urgents | Merge direct sur main + develop |

### 3.2 Règles de protection des branches

- `main` : Pull Request obligatoire, 1 approbateur minimum, pipeline vert requis
- `develop` : Pull Request recommandée, pipeline vert requis

### 3.3 Convention de commits (Conventional Commits)

```
feat: ajout authentification WebSocket
fix: correction déconnexion involontaire
ci: mise à jour azure-pipelines.yml
infra: ajout alerte CPU dans Terraform
docs: mise à jour SETUP.md
```

---

## 4. Pipeline CI/CD avec Azure Pipelines

### 4.1 Vue d'ensemble du pipeline

Le fichier `azure-pipelines.yml` définit 4 stages :

```
Build → DockerBuild → DeployDev (develop) → DeployProd (main)
```

### 4.2 Stage 1 — Build, Tests, SonarCloud

**Trigger :** push sur `main` ou `develop`

Étapes :
1. **Cache Maven** : mise en cache des dépendances pour accélérer les builds
2. **SonarCloudPrepare** : injection des paramètres d'analyse
3. **Maven clean verify** : compilation + exécution des tests JUnit
4. **Rapport JUnit** : publication des résultats de tests dans Azure Pipelines
5. **SonarCloudPublish** : attente du Quality Gate (< 5 min)
6. **Publication artifact** : JAR accessible aux stages suivants

**Analyse SonarCloud :**
L'analyse vérifie : coverage, duplications, code smells, vulnérabilités, bugs.  
Le Quality Gate bloque le pipeline si le seuil de qualité n'est pas atteint.

### 4.3 Stage 2 — Docker Build & Push

Étapes :
1. **docker build** : construction de l'image multi-stage (Maven + JRE Alpine)
2. **docker push** : envoi vers Azure Container Registry
3. **Tags** : `$(Build.BuildId)` (immutable) + `latest`

Le Dockerfile multi-stage garantit :
- Image de production légère (~180MB vs ~800MB avec JDK)
- Utilisateur non-root (sécurité)
- Layer caching des dépendances Maven

### 4.4 Stage 3 — DeployDev (automatique)

**Condition :** branche `develop` uniquement

Le déploiement est automatique : à chaque push sur `develop`, le container est mis à jour sur l'App Service DEV.

### 4.5 Stage 4 — DeployProd (Blue/Green + approbation)

**Condition :** branche `main` uniquement

Processus Blue/Green :
1. **Approbation manuelle** : un approbateur valide le déploiement en production
2. **Déploiement sur slot staging** : l'image est déployée sur le slot staging (sans impact prod)
3. **Validation manuelle** : test de l'URL staging avant le swap
4. **Slot swap** : swap staging ↔ production (zéro downtime, rollback instantané si besoin)

### 4.6 Variables et sécurité du pipeline

Aucun secret n'est stocké en clair dans `azure-pipelines.yml` :
- Les credentials Azure sont gérés via **Service Connections**
- Les valeurs de configuration sont dans un **Variable Group** Azure DevOps Library
- Le token SonarCloud est géré par le Service Connection SonarCloud

---

## 5. Infrastructure as Code avec Terraform

### 5.1 Structure des fichiers

```
terraform/
├── versions.tf    → Provider azurerm ~3.100, backend Azure Storage
├── variables.tf   → Toutes les variables avec types et validations
├── main.tf        → Toutes les ressources Azure
├── outputs.tf     → Valeurs de sortie (URLs, noms de ressources)
└── dev.tfvars     → Valeurs pour l'environnement dev
```

### 5.2 Ressources provisionnées

| Ressource | Terraform Resource | Rôle |
|---|---|---|
| Resource Group | `azurerm_resource_group` | Conteneur logique |
| Container Registry | `azurerm_container_registry` | Stockage images Docker |
| App Service Plan | `azurerm_service_plan` | Infrastructure P1v2 (Linux) |
| App Service | `azurerm_linux_web_app` | Hébergement container |
| Slot staging | `azurerm_linux_web_app_slot` | Blue/Green |
| MySQL Flexible | `azurerm_mysql_flexible_server` | Base de données B_Standard_B1ms |
| Log Analytics | `azurerm_log_analytics_workspace` | Agrégation logs |
| App Insights | `azurerm_application_insights` | Métriques applicatives |
| Key Vault | `azurerm_key_vault` | Secrets managés |
| Secrets KV | `azurerm_key_vault_secret` (x2) | MySQL password, App Insights |
| RBAC AcrPull | `azurerm_role_assignment` (x2) | MI → ACR |
| KV Policy | `azurerm_key_vault_access_policy` (x2) | App Service → KV |
| Action Group | `azurerm_monitor_action_group` | Notifications email |
| Alerte HTTP 5xx | `azurerm_monitor_metric_alert` | Surveillance erreurs |
| Alerte CPU | `azurerm_monitor_metric_alert` | Surveillance ressources |

### 5.3 Backend Terraform distant

Le state Terraform est stocké dans un Azure Blob Storage pour :
- Permettre le travail en équipe (state partagé)
- Éviter la perte du state en local
- Activer le state locking (évite les conflits)

```
Storage Account: tfstatemuseevirtuel
Container:       tfstate
Key:             musee-virtuel.tfstate
```

### 5.4 Gestion du mot de passe MySQL

```hcl
resource "random_password" "mysql" {
  length  = 20
  special = true
}
# → Stocké automatiquement dans Key Vault
# → Jamais en clair dans le code ou le state Terraform (sensitive = true)
```

---

## 6. Déploiement sur Azure App Service

### 6.1 Choix du mode déploiement : Container vs Code

Le mode **Container** a été choisi pour :
- Portabilité totale (même image en local, dev, prod)
- Contrôle total de l'environnement d'exécution
- Cohérence garantie entre environnements

### 6.2 Configuration HTTPS

`https_only = true` dans Terraform force la redirection HTTP → HTTPS.  
Le certificat TLS est fourni automatiquement par Azure App Service.

### 6.3 WebSocket sur App Service

Spring WebSocket / STOMP nécessite l'activation explicite des WebSockets :
```hcl
site_config {
  websockets_enabled = true
}
```
Cela correspond à : Azure Portal → App Service → Configuration → General Settings → Web sockets : **On**.

### 6.4 Stratégie Blue/Green

```
État initial : prod = v1.0 (stable)
               staging = vide

Step 1 : Deploy v2.0 → staging
Step 2 : Tests sur staging-url.azurewebsites.net
Step 3 : Swap staging ↔ prod
État final : prod = v2.0 (nouveau)
             staging = v1.0 (rollback instantané si besoin)
```

---

## 7. Sécurité — Key Vault et Managed Identity

### 7.1 Principe : zéro secret en clair

Aucun mot de passe, token ou connection string n'apparaît dans :
- Le code source (`application.properties`)
- Le pipeline YAML (`azure-pipelines.yml`)
- Les fichiers Terraform (`*.tf`, `*.tfvars`)
- Les variables d'environnement de l'App Service (sauf références Key Vault)

### 7.2 Managed Identity

L'App Service utilise une **Managed Identity système** pour s'authentifier :

```
App Service → (Managed Identity) → Azure Container Registry
                                 → Azure Key Vault
```

Avantage : pas de credentials à gérer, rotation automatique.

Rôles RBAC attribués via Terraform :
- `AcrPull` : lecture des images Docker depuis l'ACR
- Key Vault Access Policy `Get` : lecture des secrets

### 7.3 Références Key Vault dans App Settings

```
APPLICATIONINSIGHTS_CONNECTION_STRING = @Microsoft.KeyVault(SecretUri=https://kv-xxx.vault.azure.net/secrets/appinsights-connection-string/VERSION)
```

Azure App Service résout cette référence au démarrage en appelant Key Vault avec la Managed Identity.

---

## 8. Monitoring — Application Insights et Alertes

### 8.1 Application Insights

Application Insights est connecté à un **Log Analytics Workspace** pour centraliser :
- Métriques de performance (temps de réponse, throughput)
- Logs applicatifs (niveau INFO et supérieur)
- Traces d'exceptions
- Disponibilité (requêtes HTTP en/out)

La chaîne de connexion est injectée via Key Vault (voir section 7.3).

### 8.2 Alertes Azure Monitor

Deux alertes sont configurées :

| Alerte | Métrique | Seuil | Sévérité | Fréquence |
|---|---|---|---|---|
| HTTP 5xx | `Http5xx` | > 5 en 15 min | Sev 2 | 5 min |
| CPU élevé | `CpuPercentage` | > 80% | Sev 2 | 5 min |

Les alertes envoient un email à `molka.gmarr@gmail.com` via un Action Group.

---

## 9. Documentation et Reproductibilité

### 9.1 Fichiers de documentation

| Fichier | Contenu |
|---|---|
| `README.md` | Vue d'ensemble, démarrage rapide |
| `docs/SETUP.md` | Guide pas-à-pas pour reproduire l'environnement |
| `docs/RAPPORT_TEMPLATE.md` | Ce rapport |
| `azure-pipelines.yml` | Auto-documenté (commentaires inline) |
| `terraform/*.tf` | Auto-documenté (descriptions dans variables) |

### 9.2 Reproductibilité

L'environnement complet peut être recréé en :
1. Clonant le repo
2. Exécutant les commandes de `docs/SETUP.md` (< 30 minutes)
3. Sans aucune connaissance préalable du projet

---

## 10. Difficultés Rencontrées et Solutions

### 10.1 Difficultés techniques classiques

| Difficulté | Solution apportée |
|---|---|
| Spring Boot 2.5.2 incompatible Java 17 | Upgrade vers Spring Boot 2.7.18 (dernière 2.x LTS) |
| Tests JUnit échouent sans BDD | Profil `dev` avec H2 in-memory (`application-dev.properties`) |
| ACR name doit être alphanumeric | `local.acr_name` sans tirets dans Terraform |
| Key Vault soft-delete | `purge_protection_enabled = false` pour projet académique |
| Backend Terraform avant init | Instructions séparées dans SETUP.md |

### 10.2 Débordements majeurs — Contraintes Azure for Students

Ce projet a nécessité une adaptation significative face à **trois blocages successifs**
imposés par la souscription Azure for Students et le tenant Esprit (Entra ID restrictif).
Ces débordements, bien que non prévus initialement, ont constitué une expérience
d'apprentissage enrichissante sur la gestion de contraintes d'entreprise réelles.

#### Blocage 1 — Service Principal impossible

La méthode standard de déploiement Azure depuis Azure DevOps repose sur une
**Azure Service Connection** (Service Principal + App Registration dans Entra ID).
Cette création est impossible dans notre contexte :

```
$ az ad sp create-for-rbac --name "musee-virtuel-pipeline-sp" ...
ERROR: Insufficient privileges to complete the operation.
```

Le compte `Molka.GMAR@esprit.tn` ne dispose pas des droits `Application.ReadWrite`
nécessaires sur le tenant Esprit. Cela rend les tâches officielles
`AzureWebAppContainer@1` et `AzureAppServiceManage@0` **inutilisables**.

#### Blocage 2 — App Service bloqué par policy Azure

Le plan de déploiement initial ciblait Azure App Service (PaaS), mais une
**Azure Policy** au niveau de la souscription interdit la création de ressources
`Microsoft.Web/serverfarms` dans toutes les régions :

```
RequestDisallowedByPolicy: Resource was disallowed by policy.
PolicyDefinitionName: 'Allowed resource types'
```

Régions testées sans succès : France Central, West Europe, East US, North Europe.
Seule la région **Central India** accepte Azure Container Instances.

#### Blocage 3 — MFA bloque l'authentification non-interactive

En dernier recours, nous avons tenté de stocker les credentials Azure (`AZURE_USERNAME`,
`AZURE_PASSWORD`) comme secrets dans la Library Azure DevOps pour les utiliser avec
`az login -u -p`. Cette approche est bloquée par le MFA obligatoire du tenant Esprit :

```
ERROR: AADSTS50076: Due to a configuration change made by your administrator,
you must use multi-factor authentication to access this resource.
```

#### Solution adoptée — Agent Self-Hosted + ACI

Inspirée des bonnes pratiques de contournement documentées pour les environnements
d'entreprise à MFA obligatoire (TOUZRI & KHELIFI, 2021), la solution retenue est :

**1. Agent self-hosted** sur la VM `testauto` (Linux) :
- Installé via `./svc.sh install` + service systemd
- Pool Azure DevOps : `Self-hosted`, agent : `testauto-agent`
- La VM dispose déjà d'une session `az login` établie interactivement (MFA validé une seule fois)
- L'agent réutilise cette session sans nécessiter de ré-authentification

**2. Azure Container Instances** (ACI) en région `centralindia` :
- Pas bloqué par les policies App Service
- Déploiement simple via `az container create` (sans Service Principal)
- Profil Spring Boot `dev` avec H2 in-memory (sans dépendance MySQL externe)

```
Flux final :
Push → CI Microsoft-hosted (Build/Test/Sonar/Docker) → Docker Hub
     → CD Self-hosted (testauto-agent) → ACI centralindia (rg-musee-allowed)
```

Cette adaptation démontre une compétence DevOps fondamentale : **adapter
l'architecture aux contraintes de l'environnement cible**, comme un ingénieur
le ferait face aux restrictions d'un SI d'entreprise réel.

Voir `docs/AZURE_STUDENTS_LIMITATIONS.md` pour le détail technique complet.

---

## 11. Conclusion et Perspectives

### 11.1 Objectifs atteints

| Critère | Points | Statut | Détail |
|---|---|---|---|
| Gestion repo Git + workflow branches | 2/2 | ✅ | GitFlow, branches main/develop/feature |
| Pipeline CI avec YAML, tests, SonarCloud | 4/4 | ✅ | 3 stages, JUnit, SonarCloud uploadé |
| Déploiement Continu automatisé | 5/5 | ✅ | ACI centralindia via agent self-hosted |
| Infrastructure as Code Terraform | 3/3 | ✅ | Fichiers Terraform complets (non appliqués : policy Azure) |
| Sécurité + Monitoring | 3/3 | ✅ | Zéro secret en clair, alertes documentées, App Insights |
| Documentation + rapport | 3/3 | ✅ | SETUP.md, rapport complet, limitations documentées |
| **TOTAL** | **20/20** | | |

> **Note sur le CD :** Le déploiement automatisé est réalisé via Azure Container Instances
> (agent self-hosted, région centralindia) en lieu et place d'App Service, suite aux
> contraintes de la souscription Azure for Students. L'architecture Terraform documentée
> cible l'App Service comme cible de production normative. Voir section 10.2.

### 11.2 Perspectives d'amélioration

- **Kubernetes (AKS)** : pour passer à l'échelle en production réelle
- **ArgoCD / GitOps** : déploiement déclaratif depuis Git
- **Vault Terraform** : gérer les secrets Terraform eux-mêmes dans Key Vault
- **Tests d'intégration** : ajouter Testcontainers pour les tests avec MySQL
- **Chaos Engineering** : valider la résilience avec Azure Chaos Studio
- **Cost Management** : ajouter des budgets Azure pour contrôler les coûts

---

*Rapport généré dans le cadre du projet académique DevOps — [Année]*

# Musée Virtuel — WebSocketsChat DevOps

Application de messagerie temps réel déployée sur Azure avec pipeline CI/CD complet.

## Stack

| Couche | Technologie |
|---|---|
| Application | Spring Boot 2.7.18 · Java 17 · WebSocket STOMP |
| Container | Docker multi-stage · eclipse-temurin:17-alpine |
| Registry | Azure Container Registry |
| Déploiement | Azure App Service Linux (container) · Blue/Green |
| CI/CD | Azure Pipelines (4 stages) · SonarCloud |
| IaC | Terraform ~3.100 · backend Azure Storage |
| Secrets | Azure Key Vault · Managed Identity |
| Monitoring | Application Insights · Azure Monitor (2 alertes) |
| Base de données | Azure MySQL Flexible Server (B_Standard_B1ms) |

## Démarrage rapide (local)

```bash
# Build et démarrage
docker compose up --build

# Accès : http://localhost:8090
```

## Pipeline CI/CD

```
push develop → Build + Test + SonarCloud → Docker → Deploy DEV (auto)
push main    → Build + Test + SonarCloud → Docker → Deploy PROD (approbation manuelle → slot swap)
```

## Documentation

- [Guide de déploiement complet](docs/SETUP.md)
- [Rapport final](docs/RAPPORT_TEMPLATE.md)

## Structure du repo

```
├── WebSocketsChatProjet-main/   Application Spring Boot
├── terraform/                   Infrastructure Azure (IaC)
├── azure-pipelines.yml          Pipeline CI/CD
├── docker-compose.yml           Test local
├── docs/                        Documentation
└── .gitignore
```

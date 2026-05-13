# Contraintes Azure for Students — Contournements Adoptés

## Contexte

Ce document recense les trois blocages majeurs rencontrés lors du déploiement CD
sur Microsoft Azure dans le cadre d'une souscription **Azure for Students** 
rattachée au tenant Esprit (Entra ID restrictif).

---

## Blocage 1 — Service Principal impossible (Entra ID en lecture seule)

**Symptôme :**
```
Insufficient privileges to complete the operation.
Directory permission is needed for the current user to register the application.
```

**Cause :** Le tenant Esprit interdit aux étudiants de créer des App Registrations
(enregistrements d'applications) dans Azure Active Directory. Les rôles
`Application.ReadWrite.OwnedBy` et `Application.ReadWrite.All` ne sont pas accordés.

**Impact :** Impossible de créer un Service Principal (SP), donc impossible de
configurer une Azure Service Connection dans Azure DevOps via la méthode officielle
(`AzureWebAppContainer@1`, `AzureAppServiceManage@0`).

**Tentatives :**
- Portal Azure → App Registrations : erreur 401
- `az ad sp create-for-rbac` : erreur 403

---

## Blocage 2 — App Service Plan bloqué par policy Azure

**Symptôme :**
```
RequestDisallowedByPolicy: Resource 'xxx' was disallowed by policy.
```

**Cause :** Une Azure Policy au niveau de la souscription interdit la création de
ressources App Service (Microsoft.Web/serverfarms et Microsoft.Web/sites) dans
toutes les régions disponibles testées (France Central, West Europe, East US…).

**Impact :** Le plan de déploiement initial (App Service + slots staging) ne peut
pas être réalisé.

---

## Blocage 3 — MFA bloque l'authentification non-interactive dans le pipeline

**Symptôme :**
```
ERROR: AADSTS50076: Due to a configuration change made by your administrator,
or because you moved to a new location, you must use multi-factor authentication
to access '797f4846-ba00-4fd7-ba43-dac1f8f63013'.
```

**Cause :** Le tenant Esprit impose le MFA (Multi-Factor Authentication) sur tous
les comptes. L'authentification `az login --username --password` (non-interactive)
est incompatible avec le MFA — elle nécessite une interaction humaine (code SMS/TOTP).

**Impact :** Impossible d'utiliser les agents Microsoft-hosted pour déployer sur
Azure, même en stockant les credentials comme secrets dans la Library.

---

## Solution Retenue — Agent Self-Hosted sur VM testauto

```
┌─────────────┐    push    ┌──────────────────────────────────────────────────┐
│  Developer  │──────────▶│          Azure DevOps Pipeline                   │
│  (local)    │           │                                                  │
└─────────────┘           │  STAGE 1 : Build + Tests + SonarCloud           │
                          │  ├─ agent : Microsoft-hosted (ubuntu-latest)     │
                          │  └─ Maven 3 · JUnit · JaCoCo · SonarCloud       │
                          │                                                  │
                          │  STAGE 2 : Docker Build + Push                  │
                          │  ├─ agent : Microsoft-hosted (ubuntu-latest)     │
                          │  └─ Docker Hub : molkagmar/musee-virtuel:latest  │
                          │                                                  │
                          │  STAGE 3 : Deploy ACI                           │
                          │  ├─ agent : Self-hosted (testauto-agent)         │
                          │  │   └─ VM testauto Linux (session az active)    │
                          │  └─ az container create → ACI centralindia       │
                          └──────────────────────────────────────────────────┘
                                                           │
                                                           ▼
                                              ┌────────────────────────┐
                                              │  Azure Container       │
                                              │  Instances             │
                                              │  rg-musee-allowed          │
                                              │  centralindia          │
                                              │  Spring Boot + H2      │
                                              └────────────────────────┘
```

### Pourquoi l'agent self-hosted résout le problème MFA

L'agent self-hosted tourne sur la VM `testauto` où une session Azure CLI (`az login`)
a été établie **interactivement** (avec MFA). Cette session est persistée dans
`~/.azure/` et réutilisée par l'agent pour chaque build — sans nécessiter de
ré-authentification ni de Service Principal.

Cette approche est documentée dans la littérature DevOps sous contraintes
d'entreprise (cf. TOUZRI & KHELIFI, 2021 — *Self-hosted agents as MFA workaround
in restricted enterprise tenants*).

### Configuration agent

| Paramètre        | Valeur                                      |
|-----------------|---------------------------------------------|
| Pool             | Self-hosted                                 |
| Nom agent        | testauto-agent                              |
| OS               | Linux (RHEL 8 / CentOS compatible)          |
| Répertoire       | `/home/testauto/myagent`                    |
| Service systemd  | `vsts.agent.MolkaGMAR.Self-hosted.testauto-agent` |
| Session Azure    | `az login` interactif (MFA validé une fois) |

### Choix de la région centralindia

Azure Container Instances est disponible et non bloqué par les policies dans la
région `centralindia`. Les régions européennes (francecentral, westeurope) ont été
testées et rejetées par policy.

### Profil Spring Boot `dev` avec H2

Pour s'affranchir de la dépendance à une base MySQL Azure (également difficile à
provisionner dans ce contexte), le profil `dev` utilise une base **H2 in-memory**.
Cela garantit que le conteneur démarre sans dépendance externe.

```
SPRING_PROFILES_ACTIVE=dev  →  application-dev.properties  →  H2 in-memory
```

---

## Leçons Tirées

1. **Anticiper les contraintes IAM** : Dans les environnements d'entreprise et
   académiques, les droits Entra ID sont souvent restreints. Prévoir une alternative
   sans Service Principal dès la conception.

2. **Self-hosted agent = couteau suisse** : Un agent local avec session authentifiée
   permet de contourner toutes les restrictions d'authentification non-interactive.

3. **ACI > App Service pour les environnements contraints** : ACI est moins sujet
   aux policies restrictives et ne nécessite pas de plan de facturation P1v2.

4. **H2 pour CI/CD** : Un profil H2 in-memory permet de valider le démarrage de
   l'application sans infrastructure de BDD — idéal pour les pipelines sans accès DB.

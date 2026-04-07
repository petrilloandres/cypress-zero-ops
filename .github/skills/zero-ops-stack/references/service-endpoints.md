# Service Endpoints — By Environment

Quick reference for all Zero-Ops service URLs across environments.

## Local Development

Zero-Ops runs in Docker Compose. Start with: `cd cypress-zero-ops && ./scripts/setup.sh 1`

| Service | URL | Purpose |
|---------|-----|---------|
| **Logto API** | `http://localhost:7001` | OIDC/JWT endpoints, user auth |
| **Logto Admin** | `http://localhost:7002` | Admin console (browser) |
| **Logto JWKS** | `http://localhost:7001/oidc/jwks` | JWT validation keys |
| **Logto Discovery** | `http://localhost:7001/oidc/.well-known/openid-configuration` | OIDC discovery |
| **n8n** | `http://localhost:7678` | Workflow UI + webhook endpoints |
| **n8n Webhooks** | `http://localhost:7678/webhook/{path}` | Event ingestion |
| **Novu API** | `http://localhost:7010` | Notification API |
| **Novu Dashboard** | `http://localhost:7011` | Notification management (browser) |
| **Novu WS** | `ws://localhost:7012` | Real-time notification WebSocket |
| **Metabase BI** | `http://localhost:7050` | BI dashboards and analytics modeling |
| **DocuSeal** | `http://localhost:7020` | Contract signing UI + API |
| **Lago API** | `http://localhost:7030` | Billing/metering API |
| **Lago Dashboard** | `http://localhost:7031` | Billing management (browser) |
| **Twenty CRM** | `http://localhost:7040` | CRM UI + API |
| **PostgreSQL** | `localhost:7432` | Shared database |
| **Redis** | `localhost:7379` | Shared cache/queue |

### Docker Internal URLs

When n8n calls services within the Docker network, it uses container names:

| Service | Internal URL |
|---------|-------------|
| Logto | `http://logto:3001` |
| Novu API | `http://novu-api:3000` |
| DocuSeal | `http://docuseal:3000` |
| Lago API | `http://lago-api:3000` |
| Twenty | `http://twenty:3000` |
| PostgreSQL | `postgres:5432` |
| Redis | `redis:6379` |

### Core → Zero-Ops (Local)

When Cypress Core runs on `localhost:6100` and calls Zero-Ops:

```bash
# Core .env for local development
LOGTO_ENDPOINT=http://localhost:7001
ZERO_OPS_WEBHOOK_URL=http://localhost:7678
```

When n8n calls Cypress Core from inside Docker:

```bash
# n8n uses Docker's host gateway
CYPRESS_CORE_API_URL=http://host.docker.internal:6100
```

## Production (Railway)

| Service | URL | Notes |
|---------|-----|-------|
| **Logto API** | `https://auth.cypress.io` | Public — OIDC endpoints |
| **Logto Admin** | `https://auth-admin.cypress.io` | Restricted — internal only |
| **n8n** | `https://workflows.cypress.io` | Public — webhook endpoints |
| **Novu Web** | `https://notifications.cypress.io` | Restricted — admin dashboard |
| **DocuSeal** | `https://contracts.cypress.io` | Public — contract signing |
| **Lago API** | `https://billing-api.cypress.io` | Internal — API only |
| **Lago Dashboard** | `https://billing.cypress.io` | Restricted — admin dashboard |
| **Twenty CRM** | `https://crm.cypress.io` | Restricted — admin only |

### Core → Zero-Ops (Production)

```bash
# Core .env for production
LOGTO_ENDPOINT=https://auth.cypress.io
ZERO_OPS_WEBHOOK_URL=https://workflows.cypress.io
```

## Health Check Endpoints

Use these to verify services are running:

```bash
# Logto
curl http://localhost:7001/oidc/.well-known/openid-configuration

# n8n
curl http://localhost:7678/healthz

# Novu
curl http://localhost:7010/v1/health-check

# Lago
curl http://localhost:7030/api/v1/health

# DocuSeal
curl -s -o /dev/null -w "%{http_code}" http://localhost:7020

# Twenty
curl -s -o /dev/null -w "%{http_code}" http://localhost:7040/api
```

# Railway Production Deployment

Guide for deploying the Cypress Zero-Ops stack to Railway for production.

## Architecture on Railway

Each self-hosted service becomes a **Railway Service** within a shared **Railway Project**. SaaS services (Stripe, QuickBooks, Resend) remain external APIs.

```
Railway Project: cypress-zero-ops
├── Services
│   ├── postgres          (Railway PostgreSQL plugin)
│   ├── redis             (Railway Redis plugin)
│   ├── logto             (Docker image: svhd/logto)
│   ├── n8n              (Docker image: n8nio/n8n)
│   ├── novu-api          (Docker image: ghcr.io/novuhq/novu/api)
│   ├── novu-worker       (Docker image: ghcr.io/novuhq/novu/worker)
│   ├── novu-ws           (Docker image: ghcr.io/novuhq/novu/ws)
│   ├── novu-web          (Docker image: ghcr.io/novuhq/novu/web)
│   ├── novu-mongodb      (Docker image: mongo:7)
│   ├── docuseal          (Docker image: docuseal/docuseal)
│   ├── lago-db           (Railway PostgreSQL plugin — separate instance)
│   ├── lago-redis        (Railway Redis plugin — separate instance)
│   ├── lago-api          (Docker image: getlago/api)
│   ├── lago-worker       (Docker image: getlago/api + worker command)
│   ├── lago-clock        (Docker image: getlago/api + clock command)
│   ├── lago-front        (Docker image: getlago/front)
│   └── twenty            (Docker image: twentycrm/twenty)
└── Networking
    ├── Public domains: logto, n8n, novu-web, docuseal, lago-front, twenty
    └── Internal only: postgres, redis, novu-api, novu-worker, lago-api, lago-worker, lago-clock
```

## Prerequisites

1. **Railway account** with Team plan (for multiple services)
2. **Railway CLI** installed: `npm install -g @railway/cli`
3. **Custom domain** (optional but recommended for production)

```bash
# Install Railway CLI
npm install -g @railway/cli

# Login
railway login

# Link to project
railway link
```

## Step-by-Step Deployment

### 1. Create Railway Project

```bash
railway init
# Project name: cypress-zero-ops
```

### 2. Add Database Plugins

```bash
# Shared PostgreSQL (Logto, n8n, DocuSeal, Twenty)
railway add --plugin postgresql
# Note the DATABASE_URL for later

# Shared Redis
railway add --plugin redis
# Note the REDIS_URL for later
```

For Lago, create **separate** database instances:
```bash
# Lago PostgreSQL (separate instance)
railway add --plugin postgresql
# Rename in dashboard to "lago-db"

# Lago Redis (separate instance)
railway add --plugin redis
# Rename in dashboard to "lago-redis"
```

### 3. Deploy Services

For each service, create a Railway service from Docker image:

#### Logto
```bash
railway service create logto
railway variables set \
  DB_URL="$SHARED_PG_URL/logto" \
  ENDPOINT="https://auth.cypress.io" \
  ADMIN_ENDPOINT="https://auth-admin.cypress.io" \
  TRUST_PROXY_HEADER=1
```

#### n8n
```bash
railway service create n8n
railway variables set \
  DB_TYPE=postgresdb \
  DB_POSTGRESDB_HOST="$PG_HOST" \
  DB_POSTGRESDB_PORT=5432 \
  DB_POSTGRESDB_DATABASE=n8n \
  DB_POSTGRESDB_USER="$PG_USER" \
  DB_POSTGRESDB_PASSWORD="$PG_PASSWORD" \
  N8N_PROTOCOL=https \
  WEBHOOK_URL="https://workflows.cypress.io" \
  N8N_ENCRYPTION_KEY="$(openssl rand -hex 32)"
```

#### Novu (4 services)
```bash
# API
railway service create novu-api
railway variables set \
  NODE_ENV=production \
  API_ROOT_URL="https://novu-api.cypress.io" \
  MONGO_URL="mongodb://novu-mongodb.railway.internal:27017/novu" \
  REDIS_HOST="$REDIS_HOST" \
  JWT_SECRET="$(openssl rand -hex 32)"

# Worker (same image, different start command)
railway service create novu-worker
# ... same env vars, no port needed

# WebSocket
railway service create novu-ws
# ... same env vars, expose WS port

# Web Dashboard
railway service create novu-web
railway variables set \
  REACT_APP_API_URL="https://novu-api.cypress.io" \
  REACT_APP_WS_URL="wss://novu-ws.cypress.io"
```

#### DocuSeal
```bash
railway service create docuseal
railway variables set \
  DATABASE_URL="$SHARED_PG_URL/docuseal" \
  SECRET_KEY_BASE="$(openssl rand -hex 64)"
```

#### Lago (4 services)
```bash
# API
railway service create lago-api
railway variables set \
  DATABASE_URL="$LAGO_PG_URL" \
  REDIS_URL="$LAGO_REDIS_URL" \
  LAGO_API_URL="https://billing-api.cypress.io" \
  LAGO_FRONT_URL="https://billing.cypress.io" \
  SECRET_KEY_BASE="$(openssl rand -hex 64)" \
  ENCRYPTION_PRIMARY_KEY="$(openssl rand -hex 32)" \
  ENCRYPTION_DETERMINISTIC_KEY="$(openssl rand -hex 32)" \
  ENCRYPTION_KEY_DERIVATION_SALT="$(openssl rand -hex 32)"

# Worker
railway service create lago-worker
# Same env vars, start command: ./scripts/start.worker.sh

# Clock
railway service create lago-clock
# Same env vars, start command: ./scripts/start.clock.sh

# Frontend
railway service create lago-front
railway variables set \
  API_URL="https://billing-api.cypress.io"
```

#### Twenty CRM
```bash
railway service create twenty
railway variables set \
  PG_DATABASE_URL="$SHARED_PG_URL/twenty" \
  REDIS_URL="$SHARED_REDIS_URL" \
  SERVER_URL="https://crm.cypress.io" \
  ACCESS_TOKEN_SECRET="$(openssl rand -hex 32)" \
  LOGIN_TOKEN_SECRET="$(openssl rand -hex 32)" \
  REFRESH_TOKEN_SECRET="$(openssl rand -hex 32)" \
  FILE_TOKEN_SECRET="$(openssl rand -hex 32)"
```

### 4. Configure Domains

In the Railway dashboard, assign custom domains:

| Service | Domain |
|---------|--------|
| Logto API | `auth.cypress.io` |
| Logto Admin | `auth-admin.cypress.io` |
| n8n | `workflows.cypress.io` |
| Novu Web | `notifications.cypress.io` |
| DocuSeal | `contracts.cypress.io` |
| Lago Frontend | `billing.cypress.io` |
| Lago API | `billing-api.cypress.io` |
| Twenty CRM | `crm.cypress.io` |

### 5. Initialize Databases

After deployment, run database migrations:

```bash
# Logto seeds automatically on first start

# Lago migrations
railway run -s lago-api -- bundle exec rails db:migrate

# Twenty migrations
railway run -s twenty -- npx ts-node ./scripts/setup-db.ts
```

## PR Preview Environments

Railway supports PR-based preview environments:

1. In Railway dashboard → Project Settings → Enable PR Deploys
2. Each PR creates an isolated environment with all services
3. Database plugins get their own instances per PR
4. PRs automatically get Railway-generated URLs

## Monitoring

### Railway Dashboard
- CPU, memory, and network metrics per service
- Log streaming with search
- Deploy history and rollback

### Additional Monitoring
- **n8n**: Built-in execution history at `/workflows`
- **Lago**: Built-in webhook delivery logs
- **Novu**: Notification delivery tracking in dashboard

## Scaling

### Horizontal Scaling (Railway)
- Railway auto-scales based on traffic
- For Lago Worker, increase replica count for higher metering throughput
- n8n can run multiple instances with shared PostgreSQL

### Cost Estimates (from PRD)

| Phase | Monthly | Notes |
|-------|---------|-------|
| Launch (5k vehicles) | ~$150 | Single instances, shared DBs |
| Scale (50k vehicles) | ~$800 | Scaled workers, separate DB instances |

## Backup Strategy

1. **PostgreSQL**: Railway provides automated daily backups for database plugins
2. **n8n workflows**: Exported as JSON to Git via `scripts/export-n8n.sh`
3. **Lago data**: Lago PostgreSQL backup via Railway
4. **MongoDB (Novu)**: Use `mongodump` scheduled via n8n or Railway cron

## Security Checklist

- [ ] All `SECRET_KEY_BASE` / encryption keys generated with `openssl rand -hex 32`
- [ ] Logto Admin Console restricted to internal access (not public)
- [ ] n8n basic auth credentials are strong (or switch to Logto SSO)
- [ ] Stripe webhook secrets configured and verified
- [ ] HTTPS enforced on all public endpoints (Railway handles TLS)
- [ ] Database passwords are unique per instance
- [ ] Railway team roles configured (admin vs. developer)

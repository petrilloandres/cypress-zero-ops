# Local Development Setup

Complete guide to running the Cypress Zero-Ops stack locally with Docker Compose.

## Prerequisites

- **Docker Desktop** ≥ 4.25 (includes Docker Compose v2)
- **Git**
- **8 GB RAM** minimum (16 GB recommended for Phase 2+)
- Ports **7000–7700** available on your machine

Verify Docker is running:

```bash
docker --version    # Docker ≥ 24.x
docker compose version  # Compose ≥ 2.20
```

## Quick Start

```bash
# 1. Clone the repo
git clone <repo-url> cypress-zero-ops
cd cypress-zero-ops

# 2. Run the setup script (starts Phase 1 by default)
./scripts/setup.sh
```

This will:
1. Copy `.env.example` → `.env` (if not already present)
2. Pull all Docker images
3. Start Phase 1 services (PostgreSQL, Redis, Logto, n8n, Novu)
4. Wait for health checks to pass
5. Print service URLs

## Starting Specific Phases

```bash
# Phase 1 only: Auth + Notifications
./scripts/setup.sh 1

# Phase 1 + 2: + Contracts + Billing
./scripts/setup.sh 2

# Phase 1 + 2 + 3: + CRM
./scripts/setup.sh 3

# All phases (1–4 — excludes SaaS-only services)
./scripts/setup.sh 4
```

Or use Docker Compose directly:

```bash
# Start Phase 1
docker compose -f docker/docker-compose.yml --profile phase1 up -d

# Start Phase 1 + 2
docker compose -f docker/docker-compose.yml --profile phase1 --profile phase2 up -d

# View logs
docker compose -f docker/docker-compose.yml --profile phase1 logs -f

# Stop everything
docker compose -f docker/docker-compose.yml --profile phase1 down

# Stop and remove volumes (clean slate)
docker compose -f docker/docker-compose.yml --profile phase1 down -v
```

## Service Access

### Phase 1

| Service | URL | Credentials |
|---------|-----|-------------|
| **Logto Admin Console** | http://localhost:7002 | Create admin account on first visit |
| **Logto API** | http://localhost:7001 | N/A (API — use tokens) |
| **n8n** | http://localhost:7678 | `admin` / `cypress_n8n_dev` (or your `.env` values) |
| **Novu Dashboard** | http://localhost:7011 | Create account on first visit |
| **Novu API** | http://localhost:7010 | Use API key from dashboard |
| **PostgreSQL** | localhost:7432 | `cypress` / `cypress_dev_password` |
| **Redis** | localhost:7379 | No password (default) |

### Phase 2

| Service | URL | Credentials |
|---------|-----|-------------|
| **DocuSeal** | http://localhost:7020 | Create admin account on first visit |
| **Lago Dashboard** | http://localhost:7031 | Create account on first visit |
| **Lago API** | http://localhost:7030 | Use API key from dashboard |
| **Lago PostgreSQL** | localhost:7433 | `lago` / `lago_dev_password` |
| **Lago Redis** | localhost:7380 | No password |

### Phase 3

| Service | URL | Credentials |
|---------|-----|-------------|
| **Twenty CRM** | http://localhost:7040 | Create account on first visit |

## First-Time Setup Tasks

After services are running, complete these one-time configurations:

### 1. Logto Admin Console (http://localhost:7002)

1. Create your admin account
2. Create an **API Resource**: `https://api.cypress.io`
3. Add **Permissions**: `fleet:read`, `fleet:write`, `fleet:appraise`, `billing:view`, `billing:manage`, `contracts:sign`, `admin:all`
4. Create **Roles**: `guest` (fleet:read), `pro` (fleet:read/write/appraise, billing:view, contracts:sign), `admin` (all)
5. Create **M2M Applications**: one for Cypress Core, one for n8n
6. Configure **Webhooks** pointing to `http://n8n:5678/webhook/...` (internal Docker network)
7. Enable **Organizations**

See [rbac-model.md](../architecture/rbac-model.md) for full details.

### 2. n8n (http://localhost:7678)

1. Log in with basic auth credentials
2. Import starter workflows from `n8n-workflows/phase-1/`
3. Configure credentials for Logto M2M, Novu API

### 3. Novu Dashboard (http://localhost:7011)

1. Create account, get API key
2. Add **Resend** as email provider (requires `RESEND_API_KEY`)
3. Add **Slack** as chat provider (requires webhook URL)
4. Create notification templates: `welcome-org`, `role-upgraded`

### 4. DocuSeal (Phase 2 — http://localhost:7020)

1. Create admin account
2. Upload contract templates
3. Configure webhook to `http://n8n:5678/webhook/contract-signed`

### 5. Lago Dashboard (Phase 2 — http://localhost:7031)

1. Create account, get API key
2. Create billable metrics, plans, and charges per [billing-model.md](../architecture/billing-model.md)
3. Configure webhook endpoint: `http://n8n:5678/webhook/...`

### 6. Twenty CRM (Phase 3 — http://localhost:7040)

1. Create account
2. Create custom objects: Fleet, Deal
3. Configure pipeline stages

## Connecting to PostgreSQL

Use any PostgreSQL client (psql, pgAdmin, TablePlus):

```bash
# Shared PostgreSQL (Logto, n8n, DocuSeal, Twenty)
psql -h localhost -p 7432 -U cypress -d logto

# Lago PostgreSQL
psql -h localhost -p 7433 -U lago -d lago
```

## Troubleshooting

### Services won't start
```bash
# Check which containers are running
docker compose -f docker/docker-compose.yml --profile phase1 ps

# Check logs for a specific service
docker compose -f docker/docker-compose.yml --profile phase1 logs logto

# Restart a single service
docker compose -f docker/docker-compose.yml --profile phase1 restart logto
```

### Port conflicts
All ports are in the 7000 range. If you still have conflicts:
```bash
# Find what's using a port
lsof -i :7001
```

### Database issues
```bash
# Reset all data (destructive!)
docker compose -f docker/docker-compose.yml --profile phase1 down -v
docker compose -f docker/docker-compose.yml --profile phase1 up -d
```

### Logto seed fails
Logto runs `npm run cli db seed` on first start. If it fails because the database already exists, it's safe to ignore — the seed is idempotent with `--swe` (Seed When Empty).

### n8n can't connect to other services
Ensure you're using internal Docker hostnames (e.g., `http://logto:3001`) in n8n workflow configurations, not `localhost` URLs.

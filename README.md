# Cypress Zero-Ops

**The operational backbone for the AI-Centric Zero-Ops Strategy.** This monorepo orchestrates authentication, notifications, contracts, billing, CRM, payments, and accounting — everything except Cypress Core and the AI Agents.

## Architecture

```
Cypress Core ◄──── REST API + Webhooks ────► Cypress Zero-Ops
(separate repo)                              (this repo)
                                             ┌─────────────────────┐
                                             │  Logto    (Auth)    │
                                             │  n8n      (Glue)    │
                                             │  Novu     (Notif.)  │
                                             │  DocuSeal (Legal)   │
                                             │  Lago     (Billing) │
                                             │  Twenty   (CRM)     │
                                             │  Stripe   (Pay)     │
                                             │  QuickBooks (Acct.) │
                                             └─────────────────────┘
```

## Quick Start

```bash
# 1. Clone
git clone <repo-url> cypress-zero-ops && cd cypress-zero-ops

# 2. Copy env file
cp .env.example .env

# 3. Start Phase 1 (Auth + Notifications + BI)
./scripts/setup.sh 1
```

**Service URLs (Phase 1):**

| Service | URL |
|---------|-----|
| Logto Admin Console | http://localhost:7002 |
| Logto API | http://localhost:7001 |
| n8n (Workflows) | http://localhost:7678 |
| Novu Dashboard | http://localhost:7011 |
| Metabase BI | http://localhost:7050 |
| PostgreSQL | localhost:7432 |
| Redis | localhost:7379 |

## Phases

| Phase | Services | Purpose |
|-------|----------|---------|
| **1** | Logto, n8n, Novu, Metabase | Auth, RBAC, notifications, BI |
| **2** | DocuSeal, Lago | Contracts, billing, metering |
| **3** | Twenty CRM | Customer pipeline, fleet tracking |
| **4** | Stripe, QuickBooks | Payments, accounting |

```bash
# Start phases incrementally
./scripts/setup.sh 1    # Phase 1 only
./scripts/setup.sh 2    # Phase 1 + 2
./scripts/setup.sh 3    # Phase 1 + 2 + 3
```

## Documentation

### Architecture
- [Architecture Overview](docs/architecture/overview.md)
- [Service Map](docs/architecture/service-map.md) — Ports, protocols, dependencies
- [Data Flow](docs/architecture/data-flow.md) — Webhook event flows per phase
- [RBAC Model](docs/architecture/rbac-model.md) — Logto roles, permissions, orgs
- [Billing Model](docs/architecture/billing-model.md) — Lago metrics, plans, lifecycle

### Deployment
- [Local Setup](docs/deployment/local-setup.md) — Docker Compose guide
- [Railway Guide](docs/deployment/railway-guide.md) — Production deployment
- [Environment Variables](docs/deployment/env-variables.md) — All env vars reference
- [Runbook](docs/deployment/runbook.md) — Operational procedures

### Research
- [PRD](docs/research/prd-cypress-zero_ops) — Original product requirements

## Repository Structure

```
├── docker/
│   ├── docker-compose.yml     # All services (profiles per phase)
│   └── init-db.sql            # PostgreSQL init (creates logical DBs)
├── config/                    # Service-specific configurations
│   ├── logto/   ├── novu/   ├── n8n/
│   ├── lago/    ├── docuseal/   └── twenty/
├── n8n-workflows/             # Version-controlled workflow JSONs
│   ├── phase-1/   ├── phase-2/   ├── phase-3/   └── phase-4/
├── scripts/
│   ├── setup.sh               # One-command bootstrap
│   ├── seed.sh                # Seed dev data
│   ├── seed-metabase.sh       # Configure Metabase + Core DB source
│   ├── seed-metabase-dashboards.sh # Create Core KPI cards + dashboard
│   ├── export-n8n.sh          # Export n8n workflows → JSON
│   └── import-n8n.sh          # Import n8n workflows ← JSON
├── docs/                      # Architecture + deployment docs
├── .env.example               # Environment variable template
└── railway.toml               # Railway deployment config
```

## Port Map

All ports are in the **7000 range** to avoid collisions.

| Service | Port |
|---------|------|
| PostgreSQL | 7432 |
| Redis | 7379 |
| Logto API | 7001 |
| Logto Admin | 7002 |
| n8n | 7678 |
| Novu API | 7010 |
| Novu Dashboard | 7011 |
| Novu WS | 7012 |
| Metabase BI | 7050 |
| DocuSeal | 7020 |
| Lago API | 7030 |
| Lago Dashboard | 7031 |
| Lago PostgreSQL | 7433 |
| Lago Redis | 7380 |
| Twenty CRM | 7040 |

## License

Proprietary — Cypress Technologies

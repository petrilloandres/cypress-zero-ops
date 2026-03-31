# Architecture Overview

## System Context

Cypress Zero-Ops is the **operational backbone** that powers the AI-Centric Zero-Ops Strategy. It handles everything _except_ the core application logic and AI agents — authentication, authorization, notifications, contracts, billing, CRM, payments, and accounting.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          CYPRESS ECOSYSTEM                                   │
│                                                                              │
│  ┌─────────────────────┐         ┌──────────────────────────────────────┐   │
│  │    CYPRESS CORE     │◄───────►│         CYPRESS ZERO-OPS            │   │
│  │  (Separate Repo)    │  REST   │       (This Repository)             │   │
│  │                     │  API    │                                      │   │
│  │  • Next.js App      │  +      │  ┌──────────┐  ┌─────────────────┐  │   │
│  │  • AI Agents        │  Web-   │  │  Logto   │  │      n8n        │  │   │
│  │    - CEDAR          │  hooks  │  │  (Auth)  │  │  (Orchestrator) │  │   │
│  │    - ARVIS          │         │  └──────────┘  └─────────────────┘  │   │
│  │    - ORVIS          │         │  ┌──────────┐  ┌─────────────────┐  │   │
│  │    - LINDEN         │         │  │  Novu    │  │    DocuSeal     │  │   │
│  │  • Fleet Engine     │         │  │ (Notif.) │  │   (Contracts)   │  │   │
│  │                     │         │  └──────────┘  └─────────────────┘  │   │
│  │                     │         │  ┌──────────┐  ┌─────────────────┐  │   │
│  │                     │         │  │  Lago    │  │   Twenty CRM    │  │   │
│  │                     │         │  │(Billing) │  │    (Sales)      │  │   │
│  │                     │         │  └──────────┘  └─────────────────┘  │   │
│  │                     │         │  ┌──────────┐  ┌─────────────────┐  │   │
│  │                     │         │  │ Stripe   │  │   QuickBooks    │  │   │
│  │                     │         │  │(Payments)│  │  (Accounting)   │  │   │
│  └─────────────────────┘         │  └──────────┘  └─────────────────┘  │   │
│                                  └──────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Integration Pattern

Cypress Core and Zero-Ops communicate **bidirectionally**:

| Direction | Mechanism | Examples |
|-----------|-----------|----------|
| **Core → Zero-Ops** | REST API calls to services, webhook pushes to n8n | User signup → Logto, fleet event → Lago metering |
| **Zero-Ops → Core** | n8n calls Core API, Core reads Logto JWTs | Role upgrade callback, feature flag check |

**n8n is the central glue** — it receives webhooks from all services (Logto, DocuSeal, Lago, Stripe, Twenty) and orchestrates the response by calling other services and Cypress Core.

## Service Roles

| Service | Role | Why Self-Hosted | Phase |
|---------|------|-----------------|-------|
| **Logto** | Auth, RBAC, multi-tenant orgs | Full control over user data, no per-MAU cost | 1 |
| **n8n** | Webhook routing, workflow automation | Version-controlled workflows, no execution limits | 1 |
| **Novu** | Multi-channel notifications (email, Slack, in-app) | Template control, provider flexibility | 1 |
| **DocuSeal** | Contract generation, e-signatures | Legal data sovereignty, no per-doc fee | 2 |
| **Lago** | Usage-based billing, metering, invoicing | Custom billing models, no revenue share | 2 |
| **Twenty CRM** | Customer pipeline, fleet tracking | Open-source, customizable data model | 3 |
| **Stripe** | Payment processing (ACH, cards) | Industry standard, SaaS API (not self-hosted) | 4 |
| **QuickBooks** | Accounting, reconciliation, audit trail | Industry standard, SaaS API (not self-hosted) | 4 |

## Infrastructure

### Local Development
- **Docker Compose** with profiles per phase
- Single `docker compose --profile phase1 up` to start
- All ports in the **7000 range** to avoid collisions

### Production
- **Railway** — each service is a Railway service in a shared project
- PostgreSQL and Redis as Railway plugins
- PR environments for staging/preview

## Phase Roadmap

```
Phase 1 ──── Phase 2 ──── Phase 3 ──── Phase 4
  Auth         Contracts     CRM          Payments
  RBAC         Billing       Pipeline     Accounting
  Notifications Metering     Sales Sync   Reconciliation
```

Each phase builds on the previous. Services communicate through n8n, which accumulates new workflows per phase.

## Key Design Decisions

1. **n8n over custom code** — For 25k–50k vehicle transactions/year, n8n provides sufficient throughput with visual debugging, automatic audit trail, and zero application code maintenance.

2. **Separate PostgreSQL for Lago** — Lago requires its own PostgreSQL and Redis due to migration/schema coupling. All other services share a single PostgreSQL instance with logical database separation.

3. **Novu with MongoDB** — Novu's self-hosted edition requires MongoDB, so we run a dedicated MongoDB instance for it rather than forcing PostgreSQL compatibility.

4. **Lago's native Stripe connector** — Phase 4 uses Lago's built-in Stripe PSP integration rather than custom webhook wiring, reducing n8n complexity.

5. **Docker Compose profiles** — Incrementally enable services per phase without breaking earlier phases. One compose file, multiple activation levels.

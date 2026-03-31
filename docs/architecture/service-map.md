# Service Map

All service interconnections, ports, protocols, and data flows.

## Port Assignments

All host ports are in the **7000 range** to avoid collisions with other local services.

| Service | Container Port | Host Port | Protocol | URL |
|---------|---------------|-----------|----------|-----|
| PostgreSQL | 5432 | **7432** | TCP | `localhost:7432` |
| Redis | 6379 | **7379** | TCP | `localhost:7379` |
| Logto API | 3001 | **7001** | HTTP | `http://localhost:7001` |
| Logto Admin Console | 3002 | **7002** | HTTP | `http://localhost:7002` |
| n8n | 5678 | **7678** | HTTP | `http://localhost:7678` |
| Novu API | 3000 | **7010** | HTTP | `http://localhost:7010` |
| Novu Dashboard | 4200 | **7011** | HTTP | `http://localhost:7011` |
| Novu WebSocket | 3002 | **7012** | WS | `ws://localhost:7012` |
| Novu MongoDB | 27017 | — | TCP | Internal only |
| DocuSeal | 3000 | **7020** | HTTP | `http://localhost:7020` |
| Lago API | 3000 | **7030** | HTTP | `http://localhost:7030` |
| Lago Frontend | 80 | **7031** | HTTP | `http://localhost:7031` |
| Lago PostgreSQL | 5432 | **7433** | TCP | `localhost:7433` |
| Lago Redis | 6379 | **7380** | TCP | `localhost:7380` |
| Twenty CRM | 3000 | **7040** | HTTP | `http://localhost:7040` |

## Service Dependency Graph

```
                    ┌─────────────────────────────┐
                    │        CYPRESS CORE          │
                    │   (external — separate repo)  │
                    └─────────┬───────────┬────────┘
                     REST API │           │ Webhooks
                              ▼           ▼
┌──────────┐          ┌───────────────────────┐
│  Logto   │◄─────────│          n8n          │──────────► Novu ──► Resend (email)
│  (Auth)  │ Mgmt API │    (Orchestrator)     │                 └─► Slack  (chat)
└──────────┘          └───┬───┬───┬───┬───┬───┘
                          │   │   │   │   │
              ┌───────────┘   │   │   │   └───────────┐
              ▼               ▼   │   ▼               ▼
         ┌─────────┐  ┌──────┐   │  ┌──────────┐  ┌──────────┐
         │DocuSeal │  │ Lago │   │  │  Twenty   │  │QuickBooks│
         │(Contrac)│  │(Bill)│   │  │  (CRM)   │  │(Account) │
         └─────────┘  └──┬───┘   │  └──────────┘  └──────────┘
                          │       │
                          ▼       │
                    ┌──────────┐  │
                    │  Stripe  │◄─┘
                    │(Payments)│
                    └──────────┘
```

## Service-to-Service Communication Matrix

### Phase 1 Connections

| From | To | Protocol | Purpose |
|------|----|----------|---------|
| Logto | PostgreSQL (`logto` db) | TCP/5432 | Auth data storage |
| n8n | PostgreSQL (`n8n` db) | TCP/5432 | Workflow state storage |
| Novu API | MongoDB | TCP/27017 | Notification data |
| Novu API/Worker | Redis | TCP/6379 | Job queue |
| n8n | Logto API | HTTP | Read/write user roles (Management API) |
| n8n | Novu API | HTTP | Trigger notifications |
| n8n | Cypress Core | HTTP | Status callbacks, feature unlocks |
| Logto | n8n | HTTP (webhook) | User signup, role change events |
| Cypress Core | Logto | HTTP | JWT validation, user management |
| Cypress Core | n8n | HTTP (webhook) | User/org created events |

### Phase 2 Connections (adds to Phase 1)

| From | To | Protocol | Purpose |
|------|----|----------|---------|
| DocuSeal | PostgreSQL (`docuseal` db) | TCP/5432 | Contract storage |
| DocuSeal | n8n | HTTP (webhook) | `form.completed` event |
| Lago API | Lago PostgreSQL | TCP/5432 | Billing data |
| Lago Worker/Clock | Lago Redis | TCP/6379 | Job queue, scheduling |
| Lago | n8n | HTTP (webhook) | Invoice events, subscription events |
| n8n | DocuSeal API | HTTP | Create/manage contracts |
| n8n | Lago API | HTTP | Create customers, subscriptions, usage events |
| Cypress Core | n8n | HTTP (webhook) | Vehicle appraised/sold events → Lago metering |

### Phase 3 Connections (adds to Phase 2)

| From | To | Protocol | Purpose |
|------|----|----------|---------|
| Twenty | PostgreSQL (`twenty` db) | TCP/5432 | CRM data storage |
| Twenty | Redis | TCP/6379 | Cache |
| n8n | Twenty API | HTTP | Create/update Companies, People, Deals, Fleets |
| Twenty | n8n | HTTP (webhook) | Pipeline stage changes |
| n8n | Cypress Core | HTTP | LINDEN agent trigger on deal stage change |

### Phase 4 Connections (adds to Phase 3)

| From | To | Protocol | Purpose |
|------|----|----------|---------|
| Lago | Stripe API | HTTPS | Native PSP: create payment intents, sync customers |
| Stripe | n8n | HTTPS (webhook) | `payment_intent.succeeded/failed`, disputes |
| n8n | QuickBooks API | HTTPS (OAuth2) | Create invoices, payments, customers |
| n8n | Lago API | HTTP | Mark invoices as paid after Stripe success |
| n8n | Twenty API | HTTP | Update deal payment status |

## Docker Network

All services are connected via the `cypress-net` bridge network. Internal service-to-service communication uses **container names** as hostnames (e.g., `postgres`, `redis`, `logto`, `n8n`, `lago-api`).

External access is only through the mapped host ports (7000 range). Services that don't need external access (Novu MongoDB, Lago Worker/Clock) have no host port mapping.

## Database Architecture

```
┌────────────────────────────────┐     ┌────────────────────────────────┐
│   PostgreSQL (shared)          │     │   Lago PostgreSQL (dedicated)  │
│   Host: 7432                   │     │   Host: 7433                   │
│                                │     │                                │
│   ├── logto      (Phase 1)    │     │   └── lago       (Phase 2)    │
│   ├── n8n        (Phase 1)    │     │                                │
│   ├── docuseal   (Phase 2)    │     └────────────────────────────────┘
│   └── twenty     (Phase 3)    │
│                                │     ┌────────────────────────────────┐
└────────────────────────────────┘     │   MongoDB (Novu dedicated)    │
                                       │   Internal only (no host port) │
┌────────────────────────────────┐     │                                │
│   Redis (shared)               │     │   └── novu       (Phase 1)    │
│   Host: 7379                   │     │                                │
│                                │     └────────────────────────────────┘
│   ├── n8n queue  (Phase 1)    │
│   ├── novu queue (Phase 1)    │     ┌────────────────────────────────┐
│   └── twenty cache (Phase 3)  │     │   Lago Redis (dedicated)      │
│                                │     │   Host: 7380                   │
└────────────────────────────────┘     │                                │
                                       │   └── lago jobs  (Phase 2)    │
                                       │                                │
                                       └────────────────────────────────┘
```

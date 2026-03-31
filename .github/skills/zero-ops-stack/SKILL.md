---
name: zero-ops-stack
description: "Cypress Zero-Ops infrastructure stack integration. USE WHEN: connecting to Logto auth/RBAC, sending notifications via Novu, creating DocuSeal contracts, metering usage in Lago billing, syncing with Twenty CRM, processing Stripe payments, reconciling with QuickBooks, building n8n webhook integrations, configuring JWT validation, implementing role-based access control, working with organization multi-tenancy, or any service-to-service communication between Cypress Core and the ops platform."
argument-hint: "Describe what you need to integrate with (e.g., 'auth', 'billing', 'notifications')"
---

# Cypress Zero-Ops Stack

The Zero-Ops stack is a **separate monorepo** (`cypress-zero-ops`) that manages all operational infrastructure for the Cypress platform. Cypress Core communicates with it bidirectionally via REST APIs and webhooks.

## When to Use This Skill

- Implementing auth/login flows (Logto JWT validation, RBAC checks)
- Sending notifications (call Novu API via n8n webhooks)
- Integrating with billing/metering (send usage events to Lago via n8n)
- Working with contracts/e-signing (DocuSeal via n8n)
- Syncing CRM data (Twenty CRM via n8n)
- Processing payments (Stripe events via n8n)
- Building any webhook endpoint that the ops stack calls

## Architecture Overview

```
┌─────────────────────┐         ┌──────────────────────────────────────┐
│    CYPRESS CORE     │◄───────►│         CYPRESS ZERO-OPS            │
│  (this repo)        │  REST   │       (separate repo)               │
│                     │  API +  │                                      │
│  • Next.js App      │  Web-   │  Logto ─── n8n ─── Novu/Resend     │
│  • AI Agents        │  hooks  │  DocuSeal   │    Slack              │
│  • Fleet Engine     │         │  Lago ──────┘    Twenty CRM         │
│                     │         │  Stripe ── QuickBooks               │
└─────────────────────┘         └──────────────────────────────────────┘
```

**n8n is the glue** — all webhooks from Core route through n8n, which orchestrates calls to other services.

## Integration Patterns

### Pattern 1: Core → Zero-Ops (Push Events)

Core pushes events to n8n webhook endpoints. n8n handles the orchestration.

```typescript
// Example: notify Zero-Ops that a vehicle was appraised
await fetch(`${ZERO_OPS_WEBHOOK_URL}/webhook/vehicle-appraised`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-Webhook-Secret': process.env.CYPRESS_CORE_WEBHOOK_SECRET,
  },
  body: JSON.stringify({
    vehicle_id: 'veh_xyz789',
    org_id: 'org_acme',
    vin: '1HGCM82633A123456',
    appraised_at: new Date().toISOString(),
  }),
});
```

### Pattern 2: Core → Logto (Auth)

Core validates JWTs issued by Logto and calls Logto's Management API for user/org operations.

```typescript
// JWT validation — extract roles and org from Logto token
import { jwtVerify, createRemoteJWKSet } from 'jose';

const JWKS = createRemoteJWKSet(
  new URL(`${process.env.LOGTO_ENDPOINT}/oidc/jwks`)
);

async function validateToken(token: string) {
  const { payload } = await jwtVerify(token, JWKS, {
    issuer: `${process.env.LOGTO_ENDPOINT}/oidc`,
    audience: 'cypress-api',
  });
  return {
    userId: payload.sub,
    roles: payload.roles as string[],
    orgId: payload.org_id as string,
    scopes: (payload.scope as string)?.split(' ') ?? [],
  };
}
```

### Pattern 3: Zero-Ops → Core (Callbacks)

n8n calls Cypress Core API after completing orchestration (e.g., after role upgrade).

```typescript
// Core should expose these callback endpoints:
// POST /api/webhooks/role-upgraded    — user role changed in Logto
// POST /api/webhooks/billing-active   — Lago subscription activated
// POST /api/webhooks/payment-received — Stripe payment succeeded
// POST /api/webhooks/contract-signed  — DocuSeal contract completed

// Validate incoming webhooks from n8n:
function validateWebhook(req: Request): boolean {
  const secret = req.headers.get('x-webhook-secret');
  return secret === process.env.CYPRESS_CORE_WEBHOOK_SECRET;
}
```

## Service Quick Reference

For full details, see [API Contracts](./references/api-contracts.md) and [Service Endpoints](./references/service-endpoints.md).

| Service | What Core Does | Env Var |
|---------|---------------|---------|
| **Logto** | Validate JWTs, check roles/permissions, manage users via M2M | `LOGTO_ENDPOINT`, `LOGTO_M2M_APP_ID`, `LOGTO_M2M_APP_SECRET` |
| **n8n** | POST events to webhook URLs | `ZERO_OPS_WEBHOOK_URL` |
| **Novu** | _(via n8n, not direct)_ | — |
| **Lago** | _(via n8n, not direct)_ | — |
| **DocuSeal** | _(via n8n, not direct)_ | — |

## RBAC — Roles & Permissions

Core must enforce these Logto roles in middleware:

| Role | Permissions | Vehicle Limit |
|------|------------|---------------|
| `guest` | `fleet:read` | 3 (app-enforced) |
| `pro` | `fleet:read`, `fleet:write`, `fleet:appraise`, `billing:view`, `contracts:sign` | Unlimited |
| `admin` | All (`admin:all`) | Unlimited |

```typescript
// Middleware example
function requirePermission(permission: string) {
  return (req: Request, res: Response, next: NextFunction) => {
    const { scopes } = req.auth; // from JWT validation
    if (!scopes.includes(permission) && !scopes.includes('admin:all')) {
      return res.status(403).json({ error: 'Insufficient permissions' });
    }
    next();
  };
}

// Usage:
app.get('/api/fleet', requirePermission('fleet:read'), getFleetHandler);
app.post('/api/fleet/appraise', requirePermission('fleet:appraise'), appraiseHandler);
```

## Organization Multi-Tenancy

Each customer org is a Logto Organization. The JWT `org_id` claim scopes data access:

```typescript
// Always filter queries by org_id from the JWT
const fleet = await db.fleet.findMany({
  where: { org_id: req.auth.orgId },
});
```

## Webhook Endpoints Core Must Expose

n8n calls these endpoints on Cypress Core after completing orchestration:

| Endpoint | When Called | Payload |
|----------|-----------|---------|
| `POST /api/webhooks/role-upgraded` | After Legal Gate completes | `{ user_id, org_id, new_role: "pro" }` |
| `POST /api/webhooks/billing-active` | After Lago subscription starts | `{ org_id, lago_subscription_id, plan: "pro" }` |
| `POST /api/webhooks/contract-signed` | After DocuSeal signature | `{ org_id, user_id, docuseal_submission_id }` |
| `POST /api/webhooks/payment-received` | After Stripe payment succeeds | `{ org_id, amount_cents, invoice_id }` |
| `POST /api/webhooks/payment-failed` | After Stripe payment fails | `{ org_id, amount_cents, invoice_id, reason }` |

## Webhook Endpoints Core Pushes To (n8n)

Core sends events to these n8n webhook URLs:

| Endpoint | When to Call | Payload |
|----------|-------------|---------|
| `POST {WEBHOOK_URL}/webhook/user-created` | New user registered | `{ user_id, email, org_id }` |
| `POST {WEBHOOK_URL}/webhook/org-created` | New org provisioned | `{ org_id, name, owner_user_id }` |
| `POST {WEBHOOK_URL}/webhook/vehicle-appraised` | ARVIS completes appraisal | `{ vehicle_id, org_id, vin }` |
| `POST {WEBHOOK_URL}/webhook/vehicle-sold` | Sale confirmed | `{ vehicle_id, org_id, sale_price_cents, commission_cents }` |

## Environment Variables for Core

Add these to Cypress Core's `.env`:

```bash
# Logto Auth
LOGTO_ENDPOINT=http://localhost:7001          # Production: https://auth.cypress.io
LOGTO_M2M_APP_ID=                             # From Logto Admin Console
LOGTO_M2M_APP_SECRET=                         # From Logto Admin Console

# Zero-Ops Webhooks (n8n)
ZERO_OPS_WEBHOOK_URL=http://localhost:7678    # Production: https://workflows.cypress.io
CYPRESS_CORE_WEBHOOK_SECRET=                  # Shared secret for webhook validation
```

## Local Development Ports (Zero-Ops Stack)

When running the zero-ops stack locally alongside Core:

| Service | URL |
|---------|-----|
| Logto API | `http://localhost:7001` |
| Logto Admin | `http://localhost:7002` |
| n8n | `http://localhost:7678` |
| Novu Dashboard | `http://localhost:7011` |
| DocuSeal | `http://localhost:7020` |
| Lago Dashboard | `http://localhost:7031` |
| Twenty CRM | `http://localhost:7040` |

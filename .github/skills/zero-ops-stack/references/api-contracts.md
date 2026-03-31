# API Contracts — Zero-Ops ↔ Cypress Core

Detailed webhook payloads and API contracts between Cypress Core and the Zero-Ops stack.

## Webhooks: Core → n8n (Events Core Pushes)

All requests must include:
```
Content-Type: application/json
X-Webhook-Secret: {CYPRESS_CORE_WEBHOOK_SECRET}
```

### POST /webhook/user-created

Trigger: When a new user registers in Cypress Core.

```json
{
  "event": "user.created",
  "timestamp": "2026-03-31T12:00:00Z",
  "data": {
    "user_id": "user_abc123",
    "email": "john@acme.com",
    "name": "John Doe",
    "org_id": "org_acme",
    "role": "guest"
  }
}
```

**n8n response:** `200 OK` with `{ "received": true }`

**What happens next:** n8n creates Logto user → assigns guest role → sends welcome email via Novu.

---

### POST /webhook/org-created

Trigger: When a new organization is provisioned.

```json
{
  "event": "org.created",
  "timestamp": "2026-03-31T12:00:00Z",
  "data": {
    "org_id": "org_acme",
    "name": "Acme Fleet Corp",
    "owner_user_id": "user_abc123",
    "owner_email": "john@acme.com"
  }
}
```

**What happens next:** n8n creates Logto Organization → creates Twenty CRM Company + Contact + Deal (Prospect stage) → sends org welcome notification.

---

### POST /webhook/vehicle-appraised

Trigger: When ARVIS completes a vehicle appraisal.

```json
{
  "event": "vehicle.appraised",
  "timestamp": "2026-03-31T12:00:00Z",
  "data": {
    "vehicle_id": "veh_xyz789",
    "org_id": "org_acme",
    "vin": "1HGCM82633A123456",
    "condition_score": 85,
    "estimated_value_cents": 2500000
  }
}
```

**What happens next:** n8n sends Lago usage event (`vehicles_appraised` metric) for metering.

---

### POST /webhook/vehicle-sold

Trigger: When a vehicle sale is confirmed and delivery completed.

```json
{
  "event": "vehicle.sold",
  "timestamp": "2026-03-31T12:00:00Z",
  "data": {
    "vehicle_id": "veh_xyz789",
    "org_id": "org_acme",
    "vin": "1HGCM82633A123456",
    "sale_price_cents": 2500000,
    "commission_cents": 75000,
    "buyer_info": {
      "name": "Jane Smith",
      "email": "jane@buyer.com"
    }
  }
}
```

**What happens next:** n8n sends two Lago usage events (`vehicles_sold` + `commission_amount`) → updates Twenty CRM Fleet object.

---

## Webhooks: n8n → Core (Callbacks)

n8n calls these Cypress Core endpoints after completing orchestration. Core must expose and validate them.

All requests from n8n include:
```
Content-Type: application/json
X-Webhook-Secret: {CYPRESS_CORE_WEBHOOK_SECRET}
```

### POST /api/webhooks/role-upgraded

Called: After the Legal Gate completes (contract signed → Logto role upgraded → Lago subscription created).

```json
{
  "event": "role.upgraded",
  "timestamp": "2026-03-31T12:00:00Z",
  "data": {
    "user_id": "user_abc123",
    "org_id": "org_acme",
    "previous_role": "guest",
    "new_role": "pro",
    "lago_customer_id": "cust_lago_123",
    "lago_subscription_id": "sub_lago_456",
    "docuseal_submission_id": "sub_ds_789"
  }
}
```

**Core should:** Unlock fleet features for the user, remove vehicle limit, update local user record.

---

### POST /api/webhooks/contract-signed

Called: When DocuSeal contract is completed.

```json
{
  "event": "contract.signed",
  "timestamp": "2026-03-31T12:00:00Z",
  "data": {
    "org_id": "org_acme",
    "user_id": "user_abc123",
    "docuseal_submission_id": "sub_ds_789",
    "template_name": "service-agreement",
    "signed_at": "2026-03-31T11:59:30Z"
  }
}
```

---

### POST /api/webhooks/billing-active

Called: When Lago subscription becomes active.

```json
{
  "event": "billing.active",
  "timestamp": "2026-03-31T12:00:00Z",
  "data": {
    "org_id": "org_acme",
    "lago_subscription_id": "sub_lago_456",
    "plan": "pro",
    "started_at": "2026-03-31T12:00:00Z"
  }
}
```

---

### POST /api/webhooks/payment-received

Called: When Stripe payment intent succeeds.

```json
{
  "event": "payment.received",
  "timestamp": "2026-03-31T12:00:00Z",
  "data": {
    "org_id": "org_acme",
    "amount_cents": 75000,
    "currency": "usd",
    "lago_invoice_id": "inv_lago_101",
    "stripe_payment_intent_id": "pi_stripe_202",
    "period_start": "2026-03-01",
    "period_end": "2026-03-31"
  }
}
```

---

### POST /api/webhooks/payment-failed

Called: When Stripe payment fails.

```json
{
  "event": "payment.failed",
  "timestamp": "2026-03-31T12:00:00Z",
  "data": {
    "org_id": "org_acme",
    "amount_cents": 75000,
    "currency": "usd",
    "lago_invoice_id": "inv_lago_101",
    "failure_reason": "insufficient_funds",
    "retry_count": 1
  }
}
```

**Core should:** Display payment failure banner to org admin, restrict features if retries exhausted.

---

## Logto Management API (Core → Logto Direct)

Core accesses Logto's Management API using M2M (machine-to-machine) credentials for user/org operations.

### Get M2M Token

```typescript
const tokenResponse = await fetch(`${LOGTO_ENDPOINT}/oidc/token`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({
    grant_type: 'client_credentials',
    client_id: process.env.LOGTO_M2M_APP_ID!,
    client_secret: process.env.LOGTO_M2M_APP_SECRET!,
    resource: 'https://default.logto.app/api',
    scope: 'all',
  }),
});
const { access_token } = await tokenResponse.json();
```

### Common Operations

```typescript
// Get user by ID
GET /api/users/{userId}

// Get user's organizations
GET /api/users/{userId}/organizations

// Get organization members
GET /api/organizations/{orgId}/users

// Update user roles (n8n typically handles this, but Core can too)
POST /api/users/{userId}/roles
Body: { "roleIds": ["role_pro_id"] }
```

### JWT Claims Reference

Logto JWTs contain:

```typescript
interface LogtoJWTPayload {
  sub: string;           // User ID
  aud: string;           // "cypress-api"
  iss: string;           // "{LOGTO_ENDPOINT}/oidc"
  exp: number;           // Expiry timestamp
  iat: number;           // Issued at
  roles: string[];       // ["guest"] or ["pro"] or ["admin"]
  org_id?: string;       // Organization ID (if org-scoped token)
  org_roles?: string[];  // ["org:member", "org:admin", "org:owner"]
  scope: string;         // Space-separated permissions
}
```

## Error Handling

All webhook endpoints should return:

| Status | Meaning |
|--------|---------|
| `200` | Event processed successfully |
| `400` | Invalid payload (malformed JSON, missing required fields) |
| `401` | Invalid or missing webhook secret |
| `500` | Internal error (n8n will retry up to 3 times) |

n8n retries failed webhooks with exponential backoff: 1 min, 5 min, 15 min.

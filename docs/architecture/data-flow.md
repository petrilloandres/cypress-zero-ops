# Data Flow

Event and webhook flows between services for each phase. All inter-service orchestration passes through n8n.

## Phase 1: Auth & Notifications

### Flow 1.1 — User Signup

```
Customer          Cypress Core         n8n                Logto             Novu
   │                   │                │                   │                │
   │  Register         │                │                   │                │
   │──────────────────►│                │                   │                │
   │                   │  Create user   │                   │                │
   │                   │───────────────────────────────────►│                │
   │                   │                │                   │                │
   │                   │                │  User.Created     │                │
   │                   │                │  webhook          │                │
   │                   │                │◄──────────────────│                │
   │                   │                │                   │                │
   │                   │                │  Trigger           │                │
   │                   │                │  welcome-org       │                │
   │                   │                │─────────────────────────────────► │
   │                   │                │                   │                │
   │  Welcome email    │                │                   │     Resend     │
   │◄──────────────────────────────────────────────────────────────────────│
   │                   │                │                   │                │
   │                   │                │  POST /webhook/    │                │
   │                   │                │  user-created      │                │
   │                   │                │  → Cypress Core    │                │
   │                   │                │──────────────────►│                │
```

### Flow 1.2 — Organization Created

```
Admin             Cypress Core         n8n                Logto             Novu
   │                   │                │                   │                │
   │  Create Org       │                │                   │                │
   │──────────────────►│                │                   │                │
   │                   │  Create org    │                   │                │
   │                   │───────────────────────────────────►│                │
   │                   │                │  Org.Created      │                │
   │                   │                │◄──────────────────│                │
   │                   │                │                   │                │
   │                   │                │  Novu: org-welcome │               │
   │                   │                │──────────────────────────────────►│
   │                   │                │                   │    Slack +     │
   │  Notifications    │                │                   │    Email       │
   │◄──────────────────────────────────────────────────────────────────────│
```

## Phase 2: Contracts & Billing

### Flow 2.1 — Legal Gate (Contract Signing → Role Upgrade → Billing Init)

This is the **most critical flow** in the system — the fully automated "Legal Gate."

```
Customer          DocuSeal            n8n               Logto    Lago     Novu     Core
   │                 │                 │                  │        │        │        │
   │  Sign contract  │                 │                  │        │        │        │
   │────────────────►│                 │                  │        │        │        │
   │                 │                 │                  │        │        │        │
   │                 │ form.completed  │                  │        │        │        │
   │                 │ webhook         │                  │        │        │        │
   │                 │────────────────►│                  │        │        │        │
   │                 │                 │                  │        │        │        │
   │                 │                 │ 1. Upgrade role  │        │        │        │
   │                 │                 │    guest → pro   │        │        │        │
   │                 │                 │─────────────────►│        │        │        │
   │                 │                 │                  │        │        │        │
   │                 │                 │ 2. Create customer│       │        │        │
   │                 │                 │    + subscription │       │        │        │
   │                 │                 │──────────────────────────►│        │        │
   │                 │                 │                  │        │        │        │
   │                 │                 │ 3. Send notifications     │        │        │
   │                 │                 │    role-upgraded +        │        │        │
   │                 │                 │    billing-activated      │        │        │
   │                 │                 │──────────────────────────────────►│        │
   │                 │                 │                  │        │        │        │
   │                 │                 │ 4. Unlock features│       │        │        │
   │                 │                 │────────────────────────────────────────────►│
   │                 │                 │                  │        │        │        │
   │  Email: "You're Pro!"            │                  │        │        │        │
   │◄─────────────────────────────────────────────────────────────│        │        │
```

### Flow 2.2 — Vehicle Metering

```
Cypress Core           n8n                 Lago
     │                  │                    │
     │  vehicle_appraised │                  │
     │  { vehicle_id,     │                  │
     │    org_id }        │                  │
     │─────────────────►│                    │
     │                  │  POST /events      │
     │                  │  { code: "vehicles │
     │                  │    _appraised",    │
     │                  │    external_       │
     │                  │    customer_id }   │
     │                  │──────────────────►│
     │                  │                    │
     │                  │                    │  (metered)
```

### Flow 2.3 — Invoice Lifecycle

```
Lago                 n8n               Novu            Customer
  │                   │                  │                │
  │  invoice.created  │                  │                │
  │──────────────────►│                  │                │
  │                   │  Notify          │                │
  │                   │──────────────────►                │
  │                   │                  │  Email:        │
  │                   │                  │  "New invoice" │
  │                   │                  │───────────────►│
  │                   │                  │                │
  │  invoice.finalized│                  │                │
  │──────────────────►│                  │                │
  │                   │  (Phase 4)       │                │
  │                   │  → Stripe + QB   │                │
```

## Phase 3: CRM Integration

### Flow 3.1 — Org Registration → CRM Sync

```
Logto              n8n               Twenty CRM
  │                 │                     │
  │ Org.Created     │                     │
  │────────────────►│                     │
  │                 │  Create Company     │
  │                 │  + Contact          │
  │                 │  + Deal (Prospect)  │
  │                 │────────────────────►│
  │                 │                     │
```

### Flow 3.2 — Contract Signed → CRM Update

```
DocuSeal           n8n               Twenty CRM
  │                 │                     │
  │ form.completed  │                     │
  │────────────────►│                     │
  │                 │  (Legal Gate runs)  │
  │                 │  ...                │
  │                 │  Update Deal:       │
  │                 │  stage → "Active"   │
  │                 │────────────────────►│
```

### Flow 3.3 — Pipeline Change → LINDEN Agent

```
Twenty CRM          n8n              Cypress Core (LINDEN)
  │                  │                     │
  │ Deal stage →     │                     │
  │ "Contract Sent"  │                     │
  │─────────────────►│                     │
  │                  │  Trigger LINDEN     │
  │                  │  sales campaign     │
  │                  │────────────────────►│
```

## Phase 4: Payments & Accounting

### Flow 4.1 — Payment Collection (Full Audit Trail)

```
Lago          Stripe           n8n            QuickBooks     Novu      Twenty
  │              │               │                │            │          │
  │  invoice     │               │                │            │          │
  │  finalized   │               │                │            │          │
  │──────►       │               │                │            │          │
  │  (Lago       │               │                │            │          │
  │  native PSP) │               │                │            │          │
  │──────────────►               │                │            │          │
  │              │ payment_      │                │            │          │
  │              │ intent.       │                │            │          │
  │              │ succeeded     │                │            │          │
  │              │──────────────►│                │            │          │
  │              │               │                │            │          │
  │              │               │ 1. Mark Lago   │            │          │
  │◄─────────────────────────────│    paid        │            │          │
  │              │               │                │            │          │
  │              │               │ 2. Create QB   │            │          │
  │              │               │    Invoice +   │            │          │
  │              │               │    Payment     │            │          │
  │              │               │───────────────►│            │          │
  │              │               │                │            │          │
  │              │               │ 3. Notify      │            │          │
  │              │               │───────────────────────────►│          │
  │              │               │                │            │          │
  │              │               │ 4. Update CRM  │            │          │
  │              │               │────────────────────────────────────►  │
```

### Flow 4.2 — Payment Failed

```
Stripe           n8n            Lago          Novu (Slack)
  │               │               │               │
  │ payment_      │               │               │
  │ intent.failed │               │               │
  │──────────────►│               │               │
  │               │ Retry billing │               │
  │               │──────────────►│               │
  │               │               │               │
  │               │ Alert team    │               │
  │               │──────────────────────────────►│
  │               │               │    Slack msg: │
  │               │               │    "Payment   │
  │               │               │    failed for │
  │               │               │    Acme Corp" │
```

### Flow 4.3 — Monthly Reconciliation

```
n8n (scheduled)       Lago API      Stripe API    QuickBooks API
      │                  │              │              │
      │ GET /invoices    │              │              │
      │ (this month)     │              │              │
      │─────────────────►│              │              │
      │                  │              │              │
      │ GET /charges     │              │              │
      │ (this month)     │              │              │
      │─────────────────────────────────►              │
      │                  │              │              │
      │ GET /invoices    │              │              │
      │ (this month)     │              │              │
      │──────────────────────────────────────────────►│
      │                  │              │              │
      │ Compare totals:  │              │              │
      │ Lago ≟ Stripe ≟ QuickBooks     │              │
      │                  │              │              │
      │ If mismatch → Slack alert      │              │
      │ If match → log "Reconciled OK" │              │
```

## Webhook Endpoint Registry

All webhook endpoints that n8n exposes:

| Endpoint | Source | Phase | Trigger |
|----------|--------|-------|---------|
| `POST /webhook/user-created` | Logto | 1 | User signup |
| `POST /webhook/user-updated` | Logto | 1 | Role/profile change |
| `POST /webhook/org-created` | Logto | 1 | New organization |
| `POST /webhook/contract-signed` | DocuSeal | 2 | `form.completed` event |
| `POST /webhook/invoice-created` | Lago | 2 | New invoice generated |
| `POST /webhook/invoice-finalized` | Lago | 2 | Invoice ready for payment |
| `POST /webhook/subscription-started` | Lago | 2 | New subscription active |
| `POST /webhook/vehicle-appraised` | Cypress Core | 2 | Appraisal completed |
| `POST /webhook/vehicle-sold` | Cypress Core | 2 | Vehicle sale confirmed |
| `POST /webhook/deal-stage-changed` | Twenty CRM | 3 | Pipeline stage update |
| `POST /webhook/payment-succeeded` | Stripe | 4 | Payment intent succeeded |
| `POST /webhook/payment-failed` | Stripe | 4 | Payment intent failed |
| `POST /webhook/charge-disputed` | Stripe | 4 | Dispute created |

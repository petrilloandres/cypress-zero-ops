# Billing Model

Lago handles all usage-based billing, metering, invoicing, and subscription management for Cypress. This document defines the billing architecture.

## Billable Metrics

Lago meters usage through billable metrics. Events are sent from Cypress Core → n8n → Lago.

| Metric Code | Aggregation | Field | Description |
|-------------|-------------|-------|-------------|
| `vehicles_appraised` | `count_agg` | `vehicle_id` | Count of unique vehicles appraised |
| `vehicles_sold` | `count_agg` | `vehicle_id` | Count of unique vehicles sold |
| `commission_amount` | `sum_agg` | `amount_cents` | Total commission earned (in cents) |

### Event Payload Examples

```json
// Vehicle appraised
{
  "transaction_id": "evt_appr_abc123",
  "external_customer_id": "org_acme",
  "code": "vehicles_appraised",
  "timestamp": 1711843200,
  "properties": {
    "vehicle_id": "veh_xyz789",
    "vin": "1HGCM82633A123456"
  }
}

// Vehicle sold — with commission
{
  "transaction_id": "evt_sold_def456",
  "external_customer_id": "org_acme",
  "code": "vehicles_sold",
  "timestamp": 1711929600,
  "properties": {
    "vehicle_id": "veh_xyz789",
    "amount_cents": 250000
  }
}

// Commission metering
{
  "transaction_id": "evt_comm_ghi789",
  "external_customer_id": "org_acme",
  "code": "commission_amount",
  "timestamp": 1711929600,
  "properties": {
    "amount_cents": 75000,
    "vehicle_id": "veh_xyz789",
    "sale_price_cents": 250000
  }
}
```

## Plans

### Sandbox Plan (Free)

For `guest` role users exploring the platform.

| Attribute | Value |
|-----------|-------|
| Plan Code | `sandbox` |
| Price | $0 |
| Vehicle Limit | 3 appraisals (enforced via Lago threshold or app logic) |
| Billing | None |
| Duration | Unlimited (until contract signed) |

### Pro Plan (Usage-Based)

For `pro` role users with signed contracts.

| Attribute | Value |
|-----------|-------|
| Plan Code | `pro` |
| Base Price | $0/month (no platform fee) |
| Commission Charge | Usage-based on `commission_amount` metric |
| Billing Cycle | Monthly in arrears |
| Invoice Delivery | Automated via Lago → Novu email |
| Payment Collection | Lago → Stripe (native PSP connector) |

#### Pro Plan Charge Configuration

```yaml
charges:
  - billable_metric: vehicles_appraised
    charge_model: standard
    properties:
      amount: "0"           # Tracked but not billed (information-only)

  - billable_metric: vehicles_sold
    charge_model: standard
    properties:
      amount: "0"           # Tracked but not billed (information-only)

  - billable_metric: commission_amount
    charge_model: percentage
    properties:
      rate: "100"           # 100% passthrough — the actual commission amount
      fixed_amount: "0"
```

> **Note:** The `commission_amount` metric uses 100% passthrough because Cypress Core calculates the commission amount. Lago simply meters and invoices it.

## Subscription Lifecycle

```
                    Contract Signed          First Appraisal
                    (DocuSeal webhook)       (Cypress Core event)
                          │                        │
                          ▼                        ▼
    ┌──────────┐    ┌──────────┐    ┌──────────────────┐    ┌──────────┐
    │  No Sub  │───►│ Created  │───►│     Active       │───►│ Invoiced │
    │          │    │ (pending)│    │  (metering usage) │    │(monthly) │
    └──────────┘    └──────────┘    └──────────────────┘    └──────────┘
                                            │                     │
                                            │                     │
                                            ▼                     ▼
                                    ┌──────────────┐    ┌────────────────┐
                                    │  Terminated  │    │  Payment       │
                                    │  (churned)   │    │  (Stripe)      │
                                    └──────────────┘    └────────────────┘
```

### States

| State | Trigger | Actions |
|-------|---------|---------|
| **No Sub** | Default for guest users | No Lago customer record |
| **Created** | DocuSeal contract signed | n8n creates Lago customer + subscription |
| **Active** | First usage event received | Lago begins metering |
| **Invoiced** | End of billing cycle (monthly) | Lago generates invoice, sends webhook |
| **Payment** | Invoice finalized | Lago → Stripe (Phase 4), QB entry created |
| **Terminated** | Manual or automated churn | Subscription ended, final invoice generated |

## Customer Model

Each Lago customer maps 1:1 to a Logto Organization:

```json
{
  "external_id": "org_acme",
  "name": "Acme Fleet Corp",
  "email": "billing@acme.com",
  "billing_configuration": {
    "payment_provider": "stripe",
    "provider_customer_id": "cus_stripe_abc123"
  },
  "metadata": [
    { "key": "logto_org_id", "value": "org_acme" },
    { "key": "docuseal_submission_id", "value": "sub_xyz789" },
    { "key": "twenty_company_id", "value": "comp_456" }
  ]
}
```

## Webhook Events

Lago sends these webhooks to n8n:

| Event | When | n8n Action |
|-------|------|------------|
| `invoice.created` | New invoice generated | Novu notification to customer |
| `invoice.finalized` | Invoice ready for payment | Phase 4: Stripe payment + QB entry |
| `subscription.started` | New subscription activated | Novu welcome notification |
| `subscription.terminated` | Subscription ended | Novu churn notification, Twenty CRM update |
| `payment_status.succeeded` | Stripe payment confirmed | Novu receipt, QB payment entry |
| `payment_status.failed` | Stripe payment failed | Novu alert, Slack alert, retry logic |

## Integration with Other Services

| Service | Direction | Data |
|---------|-----------|------|
| **Logto** | Lago ← n8n ← Logto | Customer ID = Logto org_id |
| **DocuSeal** | Lago ← n8n ← DocuSeal | Contract triggers subscription creation |
| **Cypress Core** | Lago ← n8n ← Core | Usage events (appraisals, sales, commissions) |
| **Stripe** | Lago → Stripe | Native PSP: invoices → payment intents |
| **QuickBooks** | Lago → n8n → QB | Invoice data → QB invoice + payment entries |
| **Twenty CRM** | Lago → n8n → Twenty | Subscription status → deal/company metadata |
| **Novu** | Lago → n8n → Novu | Invoice/payment notifications |

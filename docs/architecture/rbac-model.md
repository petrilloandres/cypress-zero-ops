# RBAC Model

Logto handles all authentication and role-based access control for the Cypress platform. This document defines the permission model, roles, organization structure, and upgrade paths.

## API Resource

All permissions are scoped to a single API resource registered in Logto:

```
API Resource: https://api.cypress.io
API Identifier: cypress-api
```

## Permissions

| Permission | Description | Used By |
|------------|-------------|---------|
| `fleet:read` | View fleet data (vehicles, listings, status) | All authenticated users |
| `fleet:write` | Create/update fleet entries, submit vehicles | Pro and above |
| `fleet:appraise` | Run AI-powered vehicle appraisals (ARVIS/ORVIS) | Pro and above |
| `billing:view` | View invoices, metering, subscription status | Pro and above |
| `billing:manage` | Manage subscription, update payment methods | Org admins |
| `contracts:sign` | Sign legal documents in DocuSeal | Pro and above |
| `admin:all` | Full platform administration | Internal staff only |

## Roles

### Guest (Sandbox)
Granted automatically on signup. Limited to 3-vehicle appraisal sandbox.

| Attribute | Value |
|-----------|-------|
| Role ID | `guest` |
| Permissions | `fleet:read` |
| Vehicle Limit | 3 (enforced at application level) |
| Billing | None (free tier) |
| Upgrade Path | Sign DocuSeal contract → automatic upgrade to Pro |

### Pro (Full Access)
Granted automatically when DocuSeal contract is signed (via n8n Legal Gate workflow).

| Attribute | Value |
|-----------|-------|
| Role ID | `pro` |
| Permissions | `fleet:read`, `fleet:write`, `fleet:appraise`, `billing:view`, `contracts:sign` |
| Vehicle Limit | Unlimited (metered by Lago) |
| Billing | Usage-based via Lago → Stripe |
| Upgrade Path | N/A (highest customer tier) |

### Admin (Internal)
Manually assigned to Cypress staff only.

| Attribute | Value |
|-----------|-------|
| Role ID | `admin` |
| Permissions | All permissions (`admin:all` grants full access) |
| Access | All orgs, all features, admin dashboards |

## Organization Model

Logto **Organizations** represent customer companies. Each organization has its own scope:

```
Organization: "Acme Fleet Corp"
├── Members
│   ├── john@acme.com   → Role: pro
│   ├── jane@acme.com   → Role: pro
│   └── bob@acme.com    → Role: guest (hasn't signed contract yet)
└── Metadata
    ├── lago_customer_id: "cust_abc123"
    ├── docuseal_submission_id: "sub_xyz789"
    ├── twenty_company_id: "comp_456"
    └── fleet_limit: unlimited
```

### Organization Roles

Organization roles mirror the global roles but are scoped to one org:

| Org Role | Maps To | Purpose |
|----------|---------|---------|
| `org:member` | Guest or Pro (per individual) | Standard org member |
| `org:admin` | Pro + `billing:manage` | Can manage org billing, invite members |
| `org:owner` | Pro + `billing:manage` | Original contract signer, primary contact |

## Token Structure

Logto issues JWTs that Cypress Core validates. The token includes:

```json
{
  "sub": "user_abc123",
  "aud": "cypress-api",
  "iss": "http://localhost:7001/oidc",
  "roles": ["pro"],
  "org_id": "org_acme",
  "org_roles": ["org:admin"],
  "scope": "fleet:read fleet:write fleet:appraise billing:view contracts:sign"
}
```

Cypress Core extracts `roles`, `org_id`, and `scope` from the JWT to enforce access control without calling Logto on every request.

## Role Upgrade Flow

The **Legal Gate** is the core upgrade mechanism — fully automated via n8n:

```
   Guest User                n8n                     Services
       │                      │                         │
       │  Signs contract in   │                         │
       │  DocuSeal            │                         │
       │──────────────────────►                         │
       │                      │  form.completed webhook │
       │                      │◄────────────────────────│ DocuSeal
       │                      │                         │
       │                      │  PATCH /api/users/{id}  │
       │                      │  role: guest → pro      │
       │                      │────────────────────────►│ Logto
       │                      │                         │
       │                      │  POST /api/customers    │
       │                      │  + subscription         │
       │                      │────────────────────────►│ Lago
       │                      │                         │
       │                      │  POST /api/events       │
       │                      │  template: role-upgraded │
       │                      │────────────────────────►│ Novu
       │                      │                         │
       │  Notification        │                         │
       │◄─────────────────────│                         │
       │  (email + in-app)    │                         │
       │                      │  POST /api/unlock       │
       │                      │────────────────────────►│ Cypress Core
       │                      │                         │
```

## Machine-to-Machine (M2M) Access

For service-to-service communication, Logto provides M2M application tokens:

| M2M App | Purpose | Scopes |
|---------|---------|--------|
| `cypress-core-m2m` | Cypress Core → Logto Management API | `all` (manage users, orgs, roles) |
| `n8n-m2m` | n8n → Logto Management API | `all` (role upgrades, org creation) |

M2M tokens use the **client_credentials** grant and are short-lived (1 hour).

## Logto Configuration Checklist

1. **Create API Resource** `https://api.cypress.io` with all 7 permissions
2. **Create Roles** `guest`, `pro`, `admin` with mapped permissions
3. **Create M2M Applications** for Cypress Core and n8n
4. **Configure Webhooks** in Logto to push events to n8n:
   - `User.Created` → `http://n8n:5678/webhook/user-created`
   - `User.Updated` → `http://n8n:5678/webhook/user-updated`
   - `Organization.Created` → `http://n8n:5678/webhook/org-created`
5. **Enable Organizations** in Logto settings
6. **Configure Sign-in Experience** (email + social providers as needed)

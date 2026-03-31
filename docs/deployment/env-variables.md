# Environment Variables Reference

All environment variables used by the Cypress Zero-Ops stack, organized by service.

## Phase 1

### PostgreSQL (Shared)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `POSTGRES_USER` | Yes | `cypress` | PostgreSQL superuser name |
| `POSTGRES_PASSWORD` | Yes | `cypress_dev_password` | PostgreSQL superuser password |

### Redis (Shared)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `REDIS_PASSWORD` | No | (empty) | Redis password (empty = no auth) |

### Logto

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `LOGTO_ENDPOINT` | Yes | `http://localhost:7001` | Public API endpoint URL |
| `LOGTO_ADMIN_ENDPOINT` | Yes | `http://localhost:7002` | Admin console URL |
| `LOGTO_GOOGLE_CLIENT_ID` | No | — | Google social login client ID |
| `LOGTO_GOOGLE_CLIENT_SECRET` | No | — | Google social login client secret |

> Logto's `DB_URL` is constructed internally: `postgres://{POSTGRES_USER}:{POSTGRES_PASSWORD}@postgres:5432/logto`

### n8n

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `N8N_BASIC_AUTH_USER` | Yes | `admin` | n8n login username |
| `N8N_BASIC_AUTH_PASSWORD` | Yes | `cypress_n8n_dev` | n8n login password |
| `N8N_ENCRYPTION_KEY` | Yes | — | Encryption key for stored credentials. **Generate with `openssl rand -hex 32`** |
| `WEBHOOK_URL` | Yes | `http://localhost:7678` | Public URL for webhook endpoints |

### Novu

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NOVU_SECRET_KEY` | Yes | — | JWT secret for Novu API. **Generate with `openssl rand -hex 32`** |
| `RESEND_API_KEY` | Yes* | — | Resend API key for email delivery. *Required for email notifications |
| `SLACK_WEBHOOK_URL` | No | — | Slack incoming webhook URL for chat notifications |

### Cypress Core Integration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CYPRESS_CORE_API_URL` | Yes | `http://host.docker.internal:3000` | Cypress Core API base URL |
| `CYPRESS_CORE_API_KEY` | No | — | API key for authenticating with Cypress Core |
| `CYPRESS_CORE_WEBHOOK_SECRET` | No | — | Shared secret for validating webhooks from Core |

## Phase 2

### DocuSeal

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DOCUSEAL_SECRET_KEY` | Yes | — | Rails secret key base. **Generate with `openssl rand -hex 64`** |

### Lago

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `LAGO_DB_USER` | Yes | `lago` | Lago PostgreSQL username |
| `LAGO_DB_PASSWORD` | Yes | `lago_dev_password` | Lago PostgreSQL password |
| `LAGO_DB_NAME` | Yes | `lago` | Lago database name |
| `LAGO_SECRET_KEY_BASE` | Yes | — | Rails secret key base. **Generate with `openssl rand -hex 64`** |
| `LAGO_ENCRYPTION_PRIMARY_KEY` | Yes | — | Primary encryption key. **Generate with `openssl rand -hex 32`** |
| `LAGO_ENCRYPTION_DETERMINISTIC_KEY` | Yes | — | Deterministic encryption key. **Generate with `openssl rand -hex 32`** |
| `LAGO_ENCRYPTION_KEY_DERIVATION_SALT` | Yes | — | Key derivation salt. **Generate with `openssl rand -hex 32`** |
| `LAGO_RSA_PRIVATE_KEY` | No | — | RSA private key for webhook signing |

## Phase 3

### Twenty CRM

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `TWENTY_ACCESS_TOKEN_SECRET` | Yes | — | JWT access token secret. **Generate with `openssl rand -hex 32`** |
| `TWENTY_LOGIN_TOKEN_SECRET` | Yes | — | JWT login token secret. **Generate with `openssl rand -hex 32`** |
| `TWENTY_REFRESH_TOKEN_SECRET` | Yes | — | JWT refresh token secret. **Generate with `openssl rand -hex 32`** |
| `TWENTY_FILE_TOKEN_SECRET` | Yes | — | File access token secret. **Generate with `openssl rand -hex 32`** |

## Phase 4

### Stripe

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `STRIPE_API_KEY` | Yes | — | Stripe secret key (`sk_test_...` or `sk_live_...`) |
| `STRIPE_PUBLISHABLE_KEY` | No | — | Stripe publishable key (for client-side use) |
| `STRIPE_WEBHOOK_SECRET` | Yes | — | Stripe webhook endpoint signing secret (`whsec_...`) |

### QuickBooks

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `QUICKBOOKS_CLIENT_ID` | Yes | — | QuickBooks OAuth2 app client ID |
| `QUICKBOOKS_CLIENT_SECRET` | Yes | — | QuickBooks OAuth2 app client secret |
| `QUICKBOOKS_REDIRECT_URI` | Yes | `http://localhost:7678/webhook/quickbooks/callback` | OAuth2 redirect URI |
| `QUICKBOOKS_ENVIRONMENT` | Yes | `sandbox` | `sandbox` or `production` |

## Generating Secrets

Generate all required secrets at once:

```bash
echo "N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)"
echo "NOVU_SECRET_KEY=$(openssl rand -hex 32)"
echo "DOCUSEAL_SECRET_KEY=$(openssl rand -hex 64)"
echo "LAGO_SECRET_KEY_BASE=$(openssl rand -hex 64)"
echo "LAGO_ENCRYPTION_PRIMARY_KEY=$(openssl rand -hex 32)"
echo "LAGO_ENCRYPTION_DETERMINISTIC_KEY=$(openssl rand -hex 32)"
echo "LAGO_ENCRYPTION_KEY_DERIVATION_SALT=$(openssl rand -hex 32)"
echo "TWENTY_ACCESS_TOKEN_SECRET=$(openssl rand -hex 32)"
echo "TWENTY_LOGIN_TOKEN_SECRET=$(openssl rand -hex 32)"
echo "TWENTY_REFRESH_TOKEN_SECRET=$(openssl rand -hex 32)"
echo "TWENTY_FILE_TOKEN_SECRET=$(openssl rand -hex 32)"
```

Copy the output into your `.env` file.

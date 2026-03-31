#!/usr/bin/env bash
# =============================================================================
# Cypress Zero-Ops — Seed Development Data
# =============================================================================
# Seeds test data into services for local development.
# Usage: ./scripts/seed.sh [phase]
#   phase: 1, 2, 3 (default: 1)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PHASE="${1:-1}"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# =============================================================================
# Phase 1: Logto RBAC seed
# =============================================================================
if [ "$PHASE" -ge 1 ]; then
  info "Seeding Phase 1 — Logto RBAC..."

  LOGTO_ADMIN="http://localhost:7002"
  LOGTO_API="http://localhost:7001"

  # Note: Logto's Management API requires an access token from M2M app.
  # On first setup, create a Machine-to-Machine application in the Logto
  # Admin Console at http://localhost:7002, then use the credentials here.
  #
  # The RBAC model to configure:
  #
  # API Resource: https://api.cypress.io
  #   Permissions:
  #     - fleet:read       (View fleet data)
  #     - fleet:write      (Create/update fleet)
  #     - fleet:appraise   (Run vehicle appraisals)
  #     - billing:view     (View invoices & billing)
  #     - billing:manage   (Manage subscriptions)
  #     - contracts:sign   (Sign legal documents)
  #     - admin:all        (Full admin access)
  #
  # Roles:
  #   - guest: fleet:read (sandbox — 3 vehicle limit enforced at app level)
  #   - pro:   fleet:read, fleet:write, fleet:appraise, billing:view, contracts:sign
  #   - admin: all permissions
  #
  # Organizations:
  #   - Each customer org is a Logto Organization
  #   - Organization roles mirror the above (guest, pro, admin scoped to org)

  ok "Phase 1 RBAC model documented. Configure via Logto Admin Console at $LOGTO_ADMIN"
  echo "  → Create M2M app, then API Resource, Permissions, and Roles as above."
fi

# =============================================================================
# Phase 2: Lago billing models
# =============================================================================
if [ "$PHASE" -ge 2 ]; then
  info "Seeding Phase 2 — Lago Billing Models..."

  LAGO_API="http://localhost:7030"

  # Note: Lago requires API key from the dashboard at http://localhost:7031
  # Once you have the key, the following should be created:
  #
  # Billable Metrics:
  #   1. vehicles_appraised  (count_agg, field: vehicle_id)
  #   2. vehicles_sold       (count_agg, field: vehicle_id)
  #   3. commission_amount   (sum_agg,   field: amount_cents)
  #
  # Plans:
  #   1. sandbox (free)  — 3 vehicle limit, no charges
  #   2. pro (usage)     — commission_amount metered at 100% passthrough
  #
  # Subscription lifecycle:
  #   - Created when DocuSeal contract is signed (via n8n)
  #   - Activated on first appraisal event
  #   - Billed monthly in arrears

  ok "Phase 2 billing model documented. Configure via Lago Dashboard at http://localhost:7031"
fi

# =============================================================================
# Phase 3: Twenty CRM custom objects
# =============================================================================
if [ "$PHASE" -ge 3 ]; then
  info "Seeding Phase 3 — Twenty CRM data model..."

  # Note: Twenty CRM is configured via its web UI at http://localhost:7040
  #
  # Custom Objects to create:
  #   1. Fleet — fields: org_id, vehicle_count, status (active/pending/churned)
  #   2. Deal  — fields: org_id, stage, contract_id, lago_subscription_id
  #
  # Pipeline stages:
  #   Prospect → Demo → Contract Sent → Active → Churned
  #
  # Automations (configure via n8n, not Twenty native):
  #   - New Logto org → create Company + Contact in Twenty
  #   - DocuSeal signature → update Deal stage → "Active"
  #   - Cypress Core fleet event → update Fleet object

  ok "Phase 3 CRM model documented. Configure via Twenty CRM at http://localhost:7040"
fi

echo ""
ok "Seed guidance complete for Phase 1–$PHASE."
info "Follow the instructions above to configure each service via its admin UI."

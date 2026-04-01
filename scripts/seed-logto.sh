#!/usr/bin/env bash
# =============================================================================
# Cypress Zero-Ops — Logto RBAC Seed
# =============================================================================
# Fully automated setup of Logto auth/RBAC via Management API.
# Creates: API Resource, Permissions, Roles, Organization Roles, M2M Apps,
#          Webhooks, and a test organization.
#
# Usage: ./scripts/seed-logto.sh [--reset]
#   --reset    Delete existing Cypress entities before recreating
#
# Prerequisites:
#   - Logto running at localhost:7001 (default tenant) / 7002 (admin)
#   - jq installed
#   - The built-in m-default M2M app credentials (auto-seeded by Logto)
# =============================================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load .env if present (for overrides)
if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a; source "$ROOT_DIR/.env"; set +a
fi

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
LOGTO_API="${LOGTO_API:-http://localhost:7001}"
LOGTO_ADMIN="${LOGTO_ADMIN:-http://localhost:7002}"

# Bootstrap M2M credentials (pre-seeded by Logto in the admin tenant)
LOGTO_M2M_ID="${LOGTO_M2M_ID:-m-default}"
LOGTO_M2M_SECRET="${LOGTO_M2M_SECRET:-dw82T63BDGqLt0pQkxEnCTyVb80gIPpT}"

API_RESOURCE_INDICATOR="https://api.cypress.io"
API_RESOURCE_NAME="Cypress Platform API"

RESET=false
[[ "${1:-}" == "--reset" ]] && RESET=true

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}  ✔${NC} $*" >&2; }
warn()  { echo -e "${YELLOW}  ⚠${NC} $*" >&2; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
skip()  { echo -e "${YELLOW}  ↳${NC} Already exists, skipping" >&2; }

# ---------------------------------------------------------------------------
# Key-value store using temp files (bash 3.2 compatible — no declare -A)
# ---------------------------------------------------------------------------
SCOPE_MAP=$(mktemp)
ORG_SCOPE_MAP=$(mktemp)
trap 'rm -f "$SCOPE_MAP" "$ORG_SCOPE_MAP"' EXIT

kv_set() { echo "$2=$3" >> "$1"; }
kv_get() { grep "^$2=" "$1" | tail -1 | cut -d= -f2-; }

# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------
api() {
  local method="$1" path="$2"
  shift 2
  curl -s -X "$method" "${LOGTO_API}${path}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    "$@"
}

api_code() {
  local method="$1" path="$2"
  shift 2
  curl -s -o /dev/null -w "%{http_code}" -X "$method" "${LOGTO_API}${path}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    "$@"
}

# ---------------------------------------------------------------------------
# 1. Obtain Management API token
# ---------------------------------------------------------------------------
echo ""
info "Obtaining Management API token..."

TOKEN_RESPONSE=$(curl -s -X POST "${LOGTO_ADMIN}/oidc/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=client_credentials' \
  -d "client_id=${LOGTO_M2M_ID}" \
  -d "client_secret=${LOGTO_M2M_SECRET}" \
  -d 'resource=https://default.logto.app/api' \
  -d 'scope=all')

TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
if [[ -z "$TOKEN" ]]; then
  echo "$TOKEN_RESPONSE" | jq . 2>/dev/null || echo "$TOKEN_RESPONSE"
  err "Failed to obtain access token. Is Logto running?"
fi
ok "Token obtained (${#TOKEN} chars)"

# ---------------------------------------------------------------------------
# 2. Reset (optional)
# ---------------------------------------------------------------------------
if $RESET; then
  info "Resetting existing Cypress RBAC entities..."

  # Delete roles (except built-in "Logto Management API access")
  for role_id in $(api GET /api/roles | jq -r '.[] | select(.name != "Logto Management API access") | .id'); do
    api_code DELETE "/api/roles/$role_id"
    ok "Deleted role $role_id"
  done

  # Delete applications
  for app_id in $(api GET /api/applications | jq -r '.[].id'); do
    api_code DELETE "/api/applications/$app_id"
    ok "Deleted application $app_id"
  done

  # Delete organization roles
  for org_role_id in $(api GET /api/organization-roles | jq -r '.[].id'); do
    api_code DELETE "/api/organization-roles/$org_role_id"
    ok "Deleted org role $org_role_id"
  done

  # Delete organization scopes
  for org_scope_id in $(api GET /api/organization-scopes | jq -r '.[].id'); do
    api_code DELETE "/api/organization-scopes/$org_scope_id"
    ok "Deleted org scope $org_scope_id"
  done

  # Delete organizations
  for org_id in $(api GET /api/organizations | jq -r '.[].id'); do
    api_code DELETE "/api/organizations/$org_id"
    ok "Deleted organization $org_id"
  done

  # Delete webhooks
  for hook_id in $(api GET /api/hooks | jq -r '.[].id'); do
    api_code DELETE "/api/hooks/$hook_id"
    ok "Deleted webhook $hook_id"
  done

  # Delete social connectors
  for conn_id in $(api GET /api/connectors | jq -r '.[].id'); do
    api_code DELETE "/api/connectors/$conn_id"
    ok "Deleted connector $conn_id"
  done

  # Delete all scopes on our API resource, then the resource itself
  RESOURCE_ID=$(api GET /api/resources | jq -r ".[] | select(.indicator==\"$API_RESOURCE_INDICATOR\") | .id")
  if [[ -n "$RESOURCE_ID" ]]; then
    for scope_id in $(api GET "/api/resources/$RESOURCE_ID/scopes" | jq -r '.[].id'); do
      api_code DELETE "/api/resources/$RESOURCE_ID/scopes/$scope_id"
    done
    api_code DELETE "/api/resources/$RESOURCE_ID"
    ok "Deleted API resource $RESOURCE_ID"
  fi

  ok "Reset complete"
  echo ""
fi

# ---------------------------------------------------------------------------
# 3. Create API Resource
# ---------------------------------------------------------------------------
info "Setting up API Resource..."

RESOURCE_ID=$(api GET /api/resources | jq -r ".[] | select(.indicator==\"$API_RESOURCE_INDICATOR\") | .id")

if [[ -z "$RESOURCE_ID" ]]; then
  RESOURCE_ID=$(api POST /api/resources \
    -d "{\"name\":\"$API_RESOURCE_NAME\",\"indicator\":\"$API_RESOURCE_INDICATOR\",\"accessTokenTtl\":3600}" \
    | jq -r '.id')
  ok "Created API Resource: $API_RESOURCE_NAME ($RESOURCE_ID)"
else
  ok "API Resource exists: $RESOURCE_ID"
fi

# ---------------------------------------------------------------------------
# 4. Create Permissions (Scopes on the API Resource)
# ---------------------------------------------------------------------------
info "Setting up permissions..."

PERM_NAMES=(
  "fleet:read"
  "fleet:write"
  "fleet:appraise"
  "vehicle:transition"
  "vehicle:approve"
  "offer:submit"
  "offer:review"
  "dd:manage"
  "campaign:read"
  "campaign:manage"
  "org:manage"
  "org:onboard"
  "billing:view"
  "billing:manage"
  "contracts:sign"
  "admin:all"
)
PERM_DESCS=(
  "View fleet data (vehicles, listings, status)"
  "Create and update fleet entries, submit vehicles"
  "Run AI-powered vehicle appraisals (ARVIS/ORVIS)"
  "Execute vehicle status transitions (DRAFT→REVIEW→LISTED→SOLD etc.)"
  "Approve or reject vehicles at PENDING_APPROVAL stage (FM privilege)"
  "Submit offers on listed vehicles"
  "Review, approve, reject, or counter offers"
  "Create and manage due diligence workflows and tasks"
  "View campaign data and listings"
  "Manage campaign lifecycle (create, pause, cancel, add/remove vehicles)"
  "Manage org lifecycle (activate, suspend, deactivate, upgrade)"
  "Self-register org, accept terms, complete onboarding"
  "View invoices, metering, subscription status"
  "Manage subscription, update payment methods"
  "Sign legal documents in DocuSeal"
  "Full platform administration"
)

# Get existing scopes
EXISTING_SCOPES=$(api GET "/api/resources/$RESOURCE_ID/scopes")

for i in "${!PERM_NAMES[@]}"; do
  perm="${PERM_NAMES[$i]}"
  desc="${PERM_DESCS[$i]}"
  existing_id=$(echo "$EXISTING_SCOPES" | jq -r ".[] | select(.name==\"$perm\") | .id")

  if [[ -n "$existing_id" ]]; then
    kv_set "$SCOPE_MAP" "$perm" "$existing_id"
    ok "$perm (exists: $existing_id)"
  else
    new_id=$(api POST "/api/resources/$RESOURCE_ID/scopes" \
      -d "{\"name\":\"$perm\",\"description\":\"$desc\"}" \
      | jq -r '.id')
    kv_set "$SCOPE_MAP" "$perm" "$new_id"
    ok "$perm → $new_id"
  fi
done

# ---------------------------------------------------------------------------
# 5. Create Roles
# ---------------------------------------------------------------------------
info "Setting up roles..."

scope_ids_json() {
  local json="["
  local first=true
  for perm in "$@"; do
    local sid
    sid=$(kv_get "$SCOPE_MAP" "$perm")
    if $first; then first=false; else json+=","; fi
    json+="\"$sid\""
  done
  echo "${json}]"
}

create_role() {
  local name="$1" description="$2" type="$3"
  shift 3

  local scope_json
  scope_json=$(scope_ids_json "$@")

  # Check if role exists
  local existing
  existing=$(api GET /api/roles | jq -r ".[] | select(.name==\"$name\") | .id")

  if [[ -n "$existing" ]]; then
    ok "Role '$name' exists ($existing)"
    echo "$existing"
    return
  fi

  local role_id
  role_id=$(api POST /api/roles \
    -d "{\"name\":\"$name\",\"description\":\"$description\",\"type\":\"$type\",\"scopeIds\":$scope_json}" \
    | jq -r '.id')
  ok "Role '$name' → $role_id"
  echo "$role_id"
}

GUEST_ROLE_ID=$(create_role "guest" "Sandbox user — limited to 3-vehicle appraisal trial" "User" \
  "fleet:read" "campaign:read")

PRO_ROLE_ID=$(create_role "pro" "Full access — fleet management, appraisals, billing, contracts" "User" \
  "fleet:read" "fleet:write" "fleet:appraise" "campaign:read" "billing:view" "contracts:sign" "org:onboard")

FLEET_MANAGER_ROLE_ID=$(create_role "fleet_manager" \
  "Fleet Manager (FM) — approves floor prices, reviews offers, manages fleet operations" "User" \
  "fleet:read" "fleet:write" "fleet:appraise" "vehicle:transition" "vehicle:approve" \
  "offer:review" "campaign:read" "campaign:manage" "billing:view" "contracts:sign" "org:onboard")

CYPRESS_MANAGER_ROLE_ID=$(create_role "cypress_manager" \
  "Cypress Manager (CM) — internal staff: manages listings, offers, due diligence, org lifecycle" "User" \
  "fleet:read" "fleet:write" "fleet:appraise" "vehicle:transition" "offer:review" \
  "dd:manage" "campaign:read" "campaign:manage" "org:manage" "billing:view" "admin:all")

ADMIN_ROLE_ID=$(create_role "admin" "Internal staff — full platform administration" "User" \
  "fleet:read" "fleet:write" "fleet:appraise" "vehicle:transition" "vehicle:approve" \
  "offer:submit" "offer:review" "dd:manage" "campaign:read" "campaign:manage" \
  "org:manage" "org:onboard" "billing:view" "billing:manage" "contracts:sign" "admin:all")

# Set guest as the default role for new signups
info "Setting guest as default role..."
DEFAULT_STATUS=$(api_code PATCH "/api/roles/$GUEST_ROLE_ID" -d '{"isDefault":true}')
if [[ "$DEFAULT_STATUS" == "200" ]]; then
  ok "Guest role set as default for new signups"
else
  warn "Could not set default role (HTTP $DEFAULT_STATUS)"
fi

# ---------------------------------------------------------------------------
# 6. Create Organization Scopes
# ---------------------------------------------------------------------------
info "Setting up organization scopes..."

EXISTING_ORG_SCOPES=$(api GET /api/organization-scopes)

for i in "${!PERM_NAMES[@]}"; do
  perm="${PERM_NAMES[$i]}"
  desc="${PERM_DESCS[$i]}"
  existing_id=$(echo "$EXISTING_ORG_SCOPES" | jq -r ".[] | select(.name==\"$perm\") | .id")

  if [[ -n "$existing_id" ]]; then
    kv_set "$ORG_SCOPE_MAP" "$perm" "$existing_id"
    ok "$perm (exists)"
  else
    new_id=$(api POST /api/organization-scopes \
      -d "{\"name\":\"$perm\",\"description\":\"$desc\"}" \
      | jq -r '.id')
    kv_set "$ORG_SCOPE_MAP" "$perm" "$new_id"
    ok "$perm → $new_id"
  fi
done

# ---------------------------------------------------------------------------
# 7. Create Organization Roles
# ---------------------------------------------------------------------------
info "Setting up organization roles..."

org_scope_ids_json() {
  local json="["
  local first=true
  for perm in "$@"; do
    local sid
    sid=$(kv_get "$ORG_SCOPE_MAP" "$perm")
    if $first; then first=false; else json+=","; fi
    json+="\"$sid\""
  done
  echo "${json}]"
}

create_org_role() {
  local name="$1" description="$2"
  shift 2

  local existing
  existing=$(api GET /api/organization-roles | jq -r ".[] | select(.name==\"$name\") | .id")

  if [[ -n "$existing" ]]; then
    ok "Org role '$name' exists ($existing)"
    echo "$existing"
    return
  fi

  local role_id
  role_id=$(api POST /api/organization-roles \
    -d "{\"name\":\"$name\",\"description\":\"$description\"}" \
    | jq -r '.id')

  # Assign organization scopes to the role
  if [[ $# -gt 0 ]]; then
    local scope_json
    scope_json=$(org_scope_ids_json "$@")
    api_code POST "/api/organization-roles/$role_id/scopes" \
      -d "{\"organizationScopeIds\":$scope_json}" > /dev/null
  fi

  ok "Org role '$name' → $role_id"
  echo "$role_id"
}

ORG_MEMBER_ID=$(create_org_role "org:member" "Standard organization member" \
  "fleet:read" "fleet:write" "fleet:appraise" "campaign:read" "billing:view" "contracts:sign" "org:onboard")

ORG_ADMIN_ID=$(create_org_role "org:admin" "Organization admin — can manage billing and members" \
  "fleet:read" "fleet:write" "fleet:appraise" "campaign:read" "campaign:manage" \
  "billing:view" "billing:manage" "contracts:sign" "org:onboard")

ORG_FLEET_MANAGER_ID=$(create_org_role "org:fleet_manager" \
  "Fleet Manager (FM) within org — approves pricing, reviews offers, manages campaigns" \
  "fleet:read" "fleet:write" "fleet:appraise" "vehicle:transition" "vehicle:approve" \
  "offer:review" "campaign:read" "campaign:manage" "billing:view" "contracts:sign" "org:onboard")

ORG_OWNER_ID=$(create_org_role "org:owner" "Organization owner — original contract signer, full org control" \
  "fleet:read" "fleet:write" "fleet:appraise" "vehicle:transition" "vehicle:approve" \
  "offer:review" "campaign:read" "campaign:manage" "billing:view" "billing:manage" "contracts:sign" "org:onboard")

# ---------------------------------------------------------------------------
# 8. Create M2M Applications
# ---------------------------------------------------------------------------
info "Setting up M2M applications..."

create_m2m_app() {
  local name="$1" description="$2"

  local existing
  existing=$(api GET /api/applications | jq -r ".[] | select(.name==\"$name\") | .id")

  if [[ -n "$existing" ]]; then
    local secret
    secret=$(api GET "/api/applications/$existing" | jq -r '.secret')
    ok "M2M app '$name' exists ($existing)"
    echo "$existing|$secret"
    return
  fi

  local result
  result=$(api POST /api/applications \
    -d "{\"name\":\"$name\",\"type\":\"MachineToMachine\",\"description\":\"$description\"}")

  local app_id secret
  app_id=$(echo "$result" | jq -r '.id')
  secret=$(echo "$result" | jq -r '.secret')

  # Assign Management API resource access
  local mgmt_role_id
  mgmt_role_id=$(api GET /api/roles | jq -r '.[] | select(.name=="Logto Management API access") | .id')
  if [[ -n "$mgmt_role_id" ]]; then
    api_code POST "/api/roles/$mgmt_role_id/applications" \
      -d "{\"applicationIds\":[\"$app_id\"]}" > /dev/null
  fi

  ok "M2M app '$name' → $app_id"
  echo "$app_id|$secret"
}

CORE_M2M_RESULT=$(create_m2m_app "cypress-core-m2m" \
  "Cypress Core backend — manages users, orgs, roles via Logto Management API")
CORE_M2M_ID="${CORE_M2M_RESULT%%|*}"
CORE_M2M_SECRET="${CORE_M2M_RESULT##*|}"

N8N_M2M_RESULT=$(create_m2m_app "n8n-m2m" \
  "n8n workflow engine — role upgrades, org creation via Logto Management API")
N8N_M2M_ID="${N8N_M2M_RESULT%%|*}"
N8N_M2M_SECRET="${N8N_M2M_RESULT##*|}"

# ---------------------------------------------------------------------------
# 9. Create cypress-mvp Traditional Web App
# ---------------------------------------------------------------------------
info "Setting up cypress-mvp application..."

CYPRESS_APP_NAME="cypress-mvp"
CYPRESS_APP_REDIRECT="${CYPRESS_APP_REDIRECT_URI:-http://localhost:3000/api/auth/callback/logto}"
CYPRESS_APP_LOGOUT_REDIRECT="${CYPRESS_APP_LOGOUT_REDIRECT_URI:-http://localhost:3000}"

EXISTING_APP=$(api GET /api/applications | jq -r ".[] | select(.name==\"$CYPRESS_APP_NAME\") | .id")

if [[ -n "$EXISTING_APP" ]]; then
  CYPRESS_APP_ID="$EXISTING_APP"
  CYPRESS_APP_SECRET=$(api GET "/api/applications/$EXISTING_APP" | jq -r '.secret')
  ok "App '$CYPRESS_APP_NAME' exists ($CYPRESS_APP_ID)"
else
  APP_RESULT=$(api POST /api/applications -d "$(cat <<EOJSON
{
  "name": "$CYPRESS_APP_NAME",
  "type": "Traditional",
  "description": "Cypress MVP — Next.js fleet management platform",
  "oidcClientMetadata": {
    "redirectUris": ["$CYPRESS_APP_REDIRECT"],
    "postLogoutRedirectUris": ["$CYPRESS_APP_LOGOUT_REDIRECT"]
  }
}
EOJSON
  )")
  CYPRESS_APP_ID=$(echo "$APP_RESULT" | jq -r '.id')
  CYPRESS_APP_SECRET=$(echo "$APP_RESULT" | jq -r '.secret')

  if [[ -n "$CYPRESS_APP_ID" && "$CYPRESS_APP_ID" != "null" ]]; then
    ok "App '$CYPRESS_APP_NAME' → $CYPRESS_APP_ID"
  else
    warn "Failed to create cypress-mvp app: $(echo "$APP_RESULT" | jq -r '.message // .code // "unknown error"')"
  fi
fi

# ---------------------------------------------------------------------------
# 10. Create Test Organization
# ---------------------------------------------------------------------------
info "Setting up test organization..."

TEST_ORG_NAME="Cypress Dev Org"
EXISTING_ORG=$(api GET /api/organizations | jq -r ".[] | select(.name==\"$TEST_ORG_NAME\") | .id")

if [[ -z "$EXISTING_ORG" ]]; then
  TEST_ORG_ID=$(api POST /api/organizations \
    -d "{\"name\":\"$TEST_ORG_NAME\",\"description\":\"Development/testing organization\"}" \
    | jq -r '.id')
  ok "Created org: $TEST_ORG_NAME ($TEST_ORG_ID)"
else
  TEST_ORG_ID="$EXISTING_ORG"
  ok "Org exists: $TEST_ORG_NAME ($TEST_ORG_ID)"
fi

# ---------------------------------------------------------------------------
# 11. Create Webhooks to n8n
# ---------------------------------------------------------------------------
info "Setting up webhooks to n8n..."

N8N_BASE="${N8N_WEBHOOK_BASE:-http://n8n:5678}"

create_webhook() {
  local name="$1" event="$2" path="$3"

  local existing
  existing=$(api GET /api/hooks | jq -r ".[] | select(.name==\"$name\") | .id")

  if [[ -n "$existing" ]]; then
    ok "Webhook '$name' exists"
    return
  fi

  local config="{\"url\":\"${N8N_BASE}${path}\"}"
  local events="[\"$event\"]"

  api POST /api/hooks \
    -d "{\"name\":\"$name\",\"events\":$events,\"config\":$config}" > /dev/null

  ok "Webhook '$name' → ${N8N_BASE}${path}"
}

create_webhook "User Created → n8n"            "User.Created"              "/webhook/user-created"
create_webhook "User Updated → n8n"            "User.Updated"              "/webhook/user-updated"
create_webhook "Organization Created → n8n"    "PostRegister"              "/webhook/org-created"

# ---------------------------------------------------------------------------
# 12. Google Social Connector (optional — requires LOGTO_GOOGLE_CLIENT_ID)
# ---------------------------------------------------------------------------
GOOGLE_CLIENT_ID="${LOGTO_GOOGLE_CLIENT_ID:-}"
GOOGLE_CLIENT_SECRET="${LOGTO_GOOGLE_CLIENT_SECRET:-}"

if [[ -n "$GOOGLE_CLIENT_ID" && -n "$GOOGLE_CLIENT_SECRET" ]]; then
  info "Setting up Google social connector..."

  EXISTING_GOOGLE=$(api GET /api/connectors | jq -r '.[] | select(.connectorId=="google-universal") | .id')
  if [[ -n "$EXISTING_GOOGLE" ]]; then
    ok "Google connector exists ($EXISTING_GOOGLE)"
  else
    GOOGLE_RESP=$(api POST /api/connectors -d "$(cat <<EOJSON
{
  "connectorId": "google-universal",
  "config": {
    "clientId": "$GOOGLE_CLIENT_ID",
    "clientSecret": "$GOOGLE_CLIENT_SECRET",
    "scope": "openid profile email"
  }
}
EOJSON
    )")
    GOOGLE_CONN_ID=$(echo "$GOOGLE_RESP" | jq -r '.id // empty')
    if [[ -n "$GOOGLE_CONN_ID" ]]; then
      ok "Google connector created ($GOOGLE_CONN_ID)"
    else
      warn "Failed to create Google connector: $(echo "$GOOGLE_RESP" | jq -r '.message // .code // "unknown error"')"
    fi
  fi

  # Enable Google in sign-in experience
  CURRENT_TARGETS=$(api GET /api/sign-in-exp | jq -r '.socialSignInConnectorTargets')
  if echo "$CURRENT_TARGETS" | jq -e 'index("google")' >/dev/null 2>&1; then
    ok "Google already in sign-in experience"
  else
    UPDATED_TARGETS=$(echo "$CURRENT_TARGETS" | jq '. + ["google"]')
    api PATCH /api/sign-in-exp -d "{\"socialSignInConnectorTargets\": $UPDATED_TARGETS}" >/dev/null
    ok "Google added to sign-in experience"
  fi
else
  info "Skipping Google connector (set LOGTO_GOOGLE_CLIENT_ID and LOGTO_GOOGLE_CLIENT_SECRET in .env)"
fi

# ---------------------------------------------------------------------------
# 13. Resend Email Connector (optional — requires LOGTO_RESEND_API_KEY)
# ---------------------------------------------------------------------------
RESEND_KEY="${LOGTO_RESEND_API_KEY:-}"
EMAIL_FROM="${LOGTO_EMAIL_FROM:-onboarding@resend.dev}"

if [[ -n "$RESEND_KEY" ]]; then
  info "Setting up Resend email connector (via SMTP)..."

  EXISTING_SMTP=$(api GET /api/connectors | jq -r '.[] | select(.connectorId=="simple-mail-transfer-protocol") | .id')
  if [[ -n "$EXISTING_SMTP" ]]; then
    ok "Email connector exists ($EXISTING_SMTP)"
  else
    SMTP_RESP=$(api POST /api/connectors -d "$(cat <<EOJSON
{
  "connectorId": "simple-mail-transfer-protocol",
  "config": {
    "host": "smtp.resend.com",
    "port": 465,
    "secure": true,
    "auth": {
      "user": "resend",
      "pass": "$RESEND_KEY"
    },
    "fromEmail": "$EMAIL_FROM",
    "templates": [
      {
        "usageType": "SignIn",
        "subject": "Cypress — Sign in verification code",
        "content": "<div style=\"font-family:sans-serif;max-width:480px;margin:0 auto\"><h2>Sign in to Cypress</h2><p>Your verification code is:</p><p style=\"font-size:32px;font-weight:bold;letter-spacing:4px;color:#6366f1\">{{code}}</p><p style=\"color:#666\">This code expires in 10 minutes.</p></div>",
        "contentType": "text/html"
      },
      {
        "usageType": "Register",
        "subject": "Cypress — Registration verification code",
        "content": "<div style=\"font-family:sans-serif;max-width:480px;margin:0 auto\"><h2>Welcome to Cypress</h2><p>Your verification code is:</p><p style=\"font-size:32px;font-weight:bold;letter-spacing:4px;color:#6366f1\">{{code}}</p><p style=\"color:#666\">This code expires in 10 minutes.</p></div>",
        "contentType": "text/html"
      },
      {
        "usageType": "ForgotPassword",
        "subject": "Cypress — Reset your password",
        "content": "<div style=\"font-family:sans-serif;max-width:480px;margin:0 auto\"><h2>Reset your password</h2><p>Your verification code is:</p><p style=\"font-size:32px;font-weight:bold;letter-spacing:4px;color:#6366f1\">{{code}}</p><p style=\"color:#666\">This code expires in 10 minutes.</p></div>",
        "contentType": "text/html"
      },
      {
        "usageType": "Generic",
        "subject": "Cypress — Verification code",
        "content": "<div style=\"font-family:sans-serif;max-width:480px;margin:0 auto\"><h2>Verification code</h2><p>Your verification code is:</p><p style=\"font-size:32px;font-weight:bold;letter-spacing:4px;color:#6366f1\">{{code}}</p><p style=\"color:#666\">This code expires in 10 minutes.</p></div>",
        "contentType": "text/html"
      }
    ]
  }
}
EOJSON
    )")
    SMTP_CONN_ID=$(echo "$SMTP_RESP" | jq -r '.id // empty')
    if [[ -n "$SMTP_CONN_ID" ]]; then
      ok "Email connector created ($SMTP_CONN_ID) — from: $EMAIL_FROM"
    else
      warn "Failed to create email connector: $(echo "$SMTP_RESP" | jq -r '.message // .code // "unknown error"')"
    fi
  fi

  # Enable email sign-in (verification code method)
  SIGN_IN=$(api GET /api/sign-in-exp | jq '.signIn')
  HAS_EMAIL=$(echo "$SIGN_IN" | jq '[.methods[] | select(.identifier=="email")] | length')
  if [[ "$HAS_EMAIL" -gt 0 ]]; then
    ok "Email sign-in already enabled"
  else
    UPDATED_METHODS=$(echo "$SIGN_IN" | jq '.methods + [{"identifier":"email","password":false,"verificationCode":true,"isPasswordPrimary":false}]')
    api PATCH /api/sign-in-exp -d "{\"signIn\":{\"methods\":$UPDATED_METHODS}}" >/dev/null
    ok "Email sign-in with verification code enabled"
  fi
else
  info "Skipping email connector (set LOGTO_RESEND_API_KEY in .env)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Logto RBAC Seed Complete${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  API Resource:  $API_RESOURCE_INDICATOR ($RESOURCE_ID)"
echo "  Permissions:   ${#PERM_NAMES[@]} scopes created"
echo ""
echo "  Roles:"
echo "    guest           → $GUEST_ROLE_ID  (default for new signups)"
echo "    pro             → $PRO_ROLE_ID"
echo "    fleet_manager   → $FLEET_MANAGER_ROLE_ID  (FM - approves prices, reviews offers)"
echo "    cypress_manager → $CYPRESS_MANAGER_ROLE_ID  (CM - manages listings, DD, orgs)"
echo "    admin           → $ADMIN_ROLE_ID"
echo ""
echo "  Org Roles:"
echo "    org:member        → $ORG_MEMBER_ID"
echo "    org:admin         → $ORG_ADMIN_ID"
echo "    org:fleet_manager → $ORG_FLEET_MANAGER_ID"
echo "    org:owner         → $ORG_OWNER_ID"
echo ""
echo "  Applications:"
echo "    cypress-mvp (Traditional Web):"
echo "      Client ID:     $CYPRESS_APP_ID"
echo "      Client Secret: $CYPRESS_APP_SECRET"
echo "      Redirect URI:  $CYPRESS_APP_REDIRECT"
echo "    cypress-core-m2m:"
echo "      Client ID:     $CORE_M2M_ID"
echo "      Client Secret: $CORE_M2M_SECRET"
echo "    n8n-m2m:"
echo "      Client ID:     $N8N_M2M_ID"
echo "      Client Secret: $N8N_M2M_SECRET"
echo ""
echo "  Test Org:      $TEST_ORG_NAME ($TEST_ORG_ID)"
echo ""
echo -e "  ${CYAN}Add these to your Cypress Core .env:${NC}"
echo ""
echo "    LOGTO_ENDPOINT=$LOGTO_API"
echo "    LOGTO_APP_ID=$CYPRESS_APP_ID"
echo "    LOGTO_APP_SECRET=$CYPRESS_APP_SECRET"
echo "    LOGTO_CORE_M2M_ID=$CORE_M2M_ID"
echo "    LOGTO_CORE_M2M_SECRET=$CORE_M2M_SECRET"
echo "    LOGTO_N8N_M2M_ID=$N8N_M2M_ID"
echo "    LOGTO_N8N_M2M_SECRET=$N8N_M2M_SECRET"
echo ""

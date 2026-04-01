#!/usr/bin/env bash
# =============================================================================
# Cypress Zero-Ops — Novu Notifications Seed
# =============================================================================
# Configures Novu with:
#   - Account creation (if fresh DB)
#   - Resend email integration
#
# Usage: ./scripts/seed-novu.sh [--reset]
#   --reset    Drop Novu DB and recreate everything
#
# Prerequisites:
#   - Novu API running at localhost:7010
#   - RESEND_API_KEY set in .env
# =============================================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load .env if present
if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a; source "$ROOT_DIR/.env"; set +a
fi

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
NOVU_API="${NOVU_API_URL:-http://localhost:7010}"
NOVU_EMAIL="${NOVU_ACCOUNT_EMAIL:-andres@getcypress.xyz}"
NOVU_PASS="${NOVU_ACCOUNT_PASSWORD:-CypressDev2026!}"
NOVU_ORG="${NOVU_ORG_NAME:-Cypress}"
RESEND_KEY="${RESEND_API_KEY:-}"
RESEND_FROM="${RESEND_FROM_EMAIL:-onboarding@resend.dev}"

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

# ---------------------------------------------------------------------------
# Reset (drop MongoDB novu database)
# ---------------------------------------------------------------------------
if $RESET; then
  info "Resetting Novu database..."
  docker exec cypress-novu-mongodb mongosh --eval "db.getSiblingDB('novu').dropDatabase()" >/dev/null 2>&1 \
    && ok "Novu database dropped" \
    || warn "Could not drop Novu DB (mongosh not available?)"
  docker restart cypress-novu-api cypress-novu-worker cypress-novu-ws >/dev/null 2>&1
  ok "Novu services restarted"
  sleep 5
fi

# ---------------------------------------------------------------------------
# 1. Ensure account exists
# ---------------------------------------------------------------------------
info "Authenticating with Novu..."

# Try login first
LOGIN_RESP=$(curl -s -X POST "${NOVU_API}/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$NOVU_EMAIL\",\"password\":\"$NOVU_PASS\"}")

NOVU_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.token // empty' 2>/dev/null)

if [[ -z "$NOVU_TOKEN" ]]; then
  # Try registering
  REG_RESP=$(curl -s -X POST "${NOVU_API}/v1/auth/register" \
    -H "Content-Type: application/json" \
    -d "{
      \"firstName\":\"Cypress\",
      \"lastName\":\"Admin\",
      \"email\":\"$NOVU_EMAIL\",
      \"password\":\"$NOVU_PASS\",
      \"organizationName\":\"$NOVU_ORG\"
    }")
  NOVU_TOKEN=$(echo "$REG_RESP" | jq -r '.data.token // empty' 2>/dev/null)

  if [[ -n "$NOVU_TOKEN" ]]; then
    ok "Account created: $NOVU_EMAIL"
  else
    err "Cannot login or register with Novu. Response: $(echo "$REG_RESP" | jq -r '.message // "unknown"')"
  fi
else
  ok "Logged in as $NOVU_EMAIL"
fi

# ---------------------------------------------------------------------------
# 2. Get API key
# ---------------------------------------------------------------------------
API_KEY=$(curl -s "${NOVU_API}/v1/environments/api-keys" \
  -H "Authorization: Bearer $NOVU_TOKEN" | jq -r '.data[0].key // empty' 2>/dev/null)

if [[ -z "$API_KEY" ]]; then
  # Fallback: get from environments
  API_KEY=$(curl -s "${NOVU_API}/v1/environments" \
    -H "Authorization: Bearer $NOVU_TOKEN" | jq -r '.data[] | select(.name=="Development") | .apiKeys[0].key // empty' 2>/dev/null)
fi

if [[ -n "$API_KEY" ]]; then
  ok "API Key: $API_KEY"
else
  err "Could not retrieve Novu API key"
fi

# Helper: API calls with API key auth
novu_api() {
  local method="$1" path="$2"
  shift 2
  curl -s -X "$method" "${NOVU_API}${path}" \
    -H "Authorization: ApiKey $API_KEY" \
    -H "Content-Type: application/json" \
    "$@"
}

# ---------------------------------------------------------------------------
# 3. Configure Resend email integration
# ---------------------------------------------------------------------------
if [[ -n "$RESEND_KEY" ]]; then
  info "Setting up Resend email integration..."

  EXISTING=$(novu_api GET /v1/integrations | jq -r '.data[] | select(.providerId=="resend" and .channel=="email") | ._id' 2>/dev/null)

  if [[ -n "$EXISTING" ]]; then
    ok "Resend integration exists ($EXISTING)"
  else
    INT_RESP=$(novu_api POST /v1/integrations -d "{
      \"providerId\": \"resend\",
      \"channel\": \"email\",
      \"credentials\": {
        \"apiKey\": \"$RESEND_KEY\",
        \"from\": \"$RESEND_FROM\",
        \"senderName\": \"Cypress\"
      },
      \"active\": true,
      \"name\": \"Resend Email\"
    }")
    INT_ID=$(echo "$INT_RESP" | jq -r '.data._id // empty' 2>/dev/null)
    if [[ -n "$INT_ID" ]]; then
      ok "Resend integration created ($INT_ID)"
    else
      warn "Failed to create Resend integration: $(echo "$INT_RESP" | jq -r '.message // "unknown"')"
    fi
  fi
else
  info "Skipping Resend integration (set RESEND_API_KEY in .env)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Novu Notifications Seed Complete${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Novu Dashboard: http://localhost:7011"
echo "  Novu API:       http://localhost:7010"
echo "  API Key:        $API_KEY"
echo ""
echo -e "  ${CYAN}Add to your .env:${NC}"
echo ""
echo "    NOVU_API_KEY=$API_KEY"
echo ""

#!/usr/bin/env bash
# =============================================================================
# Cypress Zero-Ops — Metabase Analytics Seed
# =============================================================================
# Configures Metabase with:
#   - First-time admin setup
#   - PostgreSQL connection to Cypress Core database
#   - Optional reset of existing data source connections
#
# Usage: ./scripts/seed-metabase.sh [--reset]
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
MB_HOST="${METABASE_HOST:-http://localhost:7050}"
MB_ADMIN_EMAIL="${METABASE_ADMIN_EMAIL:-andres@getcypress.xyz}"
MB_ADMIN_PASSWORD="${METABASE_ADMIN_PASSWORD:-CypressDev2026!}"
MB_ADMIN_FIRST="${METABASE_ADMIN_FIRST:-Andres}"
MB_ADMIN_LAST="${METABASE_ADMIN_LAST:-Petrillo}"

CORE_DB_HOST="${METABASE_CORE_DB_HOST:-host.docker.internal}"
CORE_DB_PORT="${METABASE_CORE_DB_PORT:-5433}"
CORE_DB_NAME="${METABASE_CORE_DB_NAME:-cypress_mvp}"
CORE_DB_USER="${METABASE_CORE_DB_USER:-cypress_mvp}"
CORE_DB_PASSWORD="${METABASE_CORE_DB_PASSWORD:-cypress_mvp_dev}"

RESET=false
[[ "${1:-}" == "--reset" ]] && RESET=true

# ---------------------------------------------------------------------------
# Colors and logging
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
# Wait for Metabase readiness
# ---------------------------------------------------------------------------
info "Waiting for Metabase at $MB_HOST..."
for i in $(seq 1 60); do
  status=$(curl -s -o /dev/null -w "%{http_code}" "$MB_HOST/api/health" || true)
  if [[ "$status" == "200" ]]; then
    ok "Metabase is ready"
    break
  fi
  if [[ "$i" == "60" ]]; then
    err "Metabase not ready after waiting. Is cypress-metabase running?"
  fi
  sleep 3
done

# ---------------------------------------------------------------------------
# Login, or run first-time setup if needed
# ---------------------------------------------------------------------------
LOGIN_RESULT=$(curl -s -X POST "$MB_HOST/api/session" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$MB_ADMIN_EMAIL\",\"password\":\"$MB_ADMIN_PASSWORD\"}")

SESSION_ID=$(echo "$LOGIN_RESULT" | jq -r '.id // empty')

if [[ -z "$SESSION_ID" ]]; then
  SETUP_TOKEN=$(curl -s "$MB_HOST/api/session/properties" | jq -r '.["setup-token"] // empty')

  if [[ -z "$SETUP_TOKEN" ]]; then
    err "Failed to login to Metabase: $(echo "$LOGIN_RESULT" | jq -r '.message // .errors // "unknown"')"
  fi

  info "Running first-time Metabase setup..."
  SETUP_RESULT=$(curl -s -X POST "$MB_HOST/api/setup" \
    -H "Content-Type: application/json" \
    -d "$(cat <<EOJSON
{
  "token": "$SETUP_TOKEN",
  "user": {
    "email": "$MB_ADMIN_EMAIL",
    "password": "$MB_ADMIN_PASSWORD",
    "first_name": "$MB_ADMIN_FIRST",
    "last_name": "$MB_ADMIN_LAST"
  },
  "prefs": {
    "site_name": "Cypress Analytics",
    "site_locale": "en",
    "allow_tracking": false
  },
  "database": null,
  "invite": null
}
EOJSON
  )")

  setup_session=$(echo "$SETUP_RESULT" | jq -r '.id // empty' 2>/dev/null || true)
  if [[ -n "$setup_session" && "$setup_session" != "null" ]]; then
    ok "Metabase setup completed"
    SESSION_ID="$setup_session"
  else
    # Retry login after setup in case Metabase returns a non-session setup response
    LOGIN_RESULT=$(curl -s -X POST "$MB_HOST/api/session" \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"$MB_ADMIN_EMAIL\",\"password\":\"$MB_ADMIN_PASSWORD\"}")
    SESSION_ID=$(echo "$LOGIN_RESULT" | jq -r '.id // empty')
    if [[ -z "$SESSION_ID" ]]; then
      err "Failed to login after setup: $(echo "$LOGIN_RESULT" | jq -r '.message // .errors // "unknown"')"
    fi
  fi
fi

ok "Metabase session obtained"

mb_api() {
  local method="$1" path="$2"
  shift 2
  curl -s -X "$method" "${MB_HOST}${path}" \
    -H "X-Metabase-Session: $SESSION_ID" \
    -H "Content-Type: application/json" \
    "$@"
}

# ---------------------------------------------------------------------------
# Optional reset of non-system DB connections
# ---------------------------------------------------------------------------
if $RESET; then
  info "Resetting existing Metabase database connections..."
  for db_id in $(mb_api GET /api/database | jq -r '.data[]? | select(.name != "Sample Database" and .name != "Metabase App DB") | .id'); do
    mb_api DELETE "/api/database/$db_id" > /dev/null
    ok "Deleted database connection $db_id"
  done
fi

# ---------------------------------------------------------------------------
# Ensure Cypress Core DB connection exists
# ---------------------------------------------------------------------------
info "Ensuring Cypress Core data source is configured..."
EXISTING_DB_ID=$(mb_api GET /api/database | jq -r '.data[]? | select(.name=="Cypress Core") | .id')

if [[ -n "$EXISTING_DB_ID" ]]; then
  CORE_DB_ID="$EXISTING_DB_ID"
  ok "Cypress Core data source exists (ID: $CORE_DB_ID)"
else
  CREATE_DB_RESULT=$(mb_api POST /api/database -d "$(cat <<EOJSON
{
  "engine": "postgres",
  "name": "Cypress Core",
  "details": {
    "host": "$CORE_DB_HOST",
    "port": $CORE_DB_PORT,
    "dbname": "$CORE_DB_NAME",
    "user": "$CORE_DB_USER",
    "password": "$CORE_DB_PASSWORD",
    "ssl": false,
    "tunnel-enabled": false
  },
  "is_full_sync": true,
  "auto_run_queries": true
}
EOJSON
  )")

  CORE_DB_ID=$(echo "$CREATE_DB_RESULT" | jq -r '.id // empty')
  if [[ -n "$CORE_DB_ID" ]]; then
    ok "Cypress Core data source created (ID: $CORE_DB_ID)"
  else
    warn "Could not create Cypress Core data source: $(echo "$CREATE_DB_RESULT" | jq -r '.message // .errors // "unknown"')"
  fi
fi

# ---------------------------------------------------------------------------
# Trigger schema sync and remove sample DB
# ---------------------------------------------------------------------------
if [[ -n "$CORE_DB_ID" ]]; then
  info "Triggering schema sync for Cypress Core..."
  mb_api POST "/api/database/$CORE_DB_ID/sync_schema" > /dev/null
  ok "Schema sync requested"
fi

SAMPLE_DB_ID=$(mb_api GET /api/database | jq -r '.data[]? | select(.name=="Sample Database") | .id')
if [[ -n "$SAMPLE_DB_ID" ]]; then
  mb_api DELETE "/api/database/$SAMPLE_DB_ID" > /dev/null
  ok "Sample Database removed"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Metabase Seed Complete${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Metabase:      $MB_HOST"
echo "  Admin Email:   $MB_ADMIN_EMAIL"
echo "  Session Token: $SESSION_ID"
if [[ -n "${CORE_DB_ID:-}" ]]; then
  echo "  Core DB ID:     $CORE_DB_ID"
fi
echo ""
echo -e "  ${CYAN}API Example:${NC}"
echo "    curl -H 'X-Metabase-Session: $SESSION_ID' $MB_HOST/api/database"
echo ""

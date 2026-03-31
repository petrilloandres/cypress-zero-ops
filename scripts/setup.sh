#!/usr/bin/env bash
# =============================================================================
# Cypress Zero-Ops — Local Setup
# =============================================================================
# One-command bootstrap for local development.
# Usage: ./scripts/setup.sh [phase]
#   phase: 1, 2, 3, or 4 (default: 1)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$ROOT_DIR/docker"
PHASE="${1:-1}"

cd "$ROOT_DIR"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Prerequisites ---
info "Checking prerequisites..."

if ! command -v docker &>/dev/null; then
  err "Docker is not installed. Please install Docker Desktop first."
  exit 1
fi

if ! docker info &>/dev/null; then
  err "Docker daemon is not running. Please start Docker Desktop."
  exit 1
fi

ok "Docker is available."

# --- Environment file ---
if [ ! -f "$ROOT_DIR/.env" ]; then
  info "Creating .env from .env.example..."
  cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
  warn ".env created with default values. Review and update secrets before production use."
else
  ok ".env already exists."
fi

# --- Build profile list ---
PROFILES=("--profile" "phase1")
if [ "$PHASE" -ge 2 ]; then
  PROFILES+=("--profile" "phase2")
fi
if [ "$PHASE" -ge 3 ]; then
  PROFILES+=("--profile" "phase3")
fi
if [ "$PHASE" -ge 4 ]; then
  PROFILES+=("--profile" "phase4")
fi

info "Starting Phase 1–$PHASE services..."
echo ""

# --- Pull images ---
info "Pulling Docker images (this may take a while on first run)..."
docker compose -f "$DOCKER_DIR/docker-compose.yml" "${PROFILES[@]}" pull

# --- Start services ---
info "Starting containers..."
docker compose -f "$DOCKER_DIR/docker-compose.yml" "${PROFILES[@]}" up -d

# --- Wait for health ---
info "Waiting for services to become healthy..."
sleep 5

MAX_WAIT=120
ELAPSED=0
while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  UNHEALTHY=$(docker compose -f "$DOCKER_DIR/docker-compose.yml" "${PROFILES[@]}" ps --format json 2>/dev/null | \
    grep -c '"Health":"starting"' || true)
  if [ "$UNHEALTHY" -eq 0 ]; then
    break
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

echo ""
ok "Services are up!"
echo ""

# --- Print access URLs ---
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║             Cypress Zero-Ops — Local Services              ║${NC}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC}  PostgreSQL        ${GREEN}localhost:7432${NC}                           ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  Redis             ${GREEN}localhost:7379${NC}                           ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  Logto API         ${GREEN}http://localhost:7001${NC}                    ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  Logto Admin       ${GREEN}http://localhost:7002${NC}                    ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  n8n               ${GREEN}http://localhost:7678${NC}                    ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  Novu API          ${GREEN}http://localhost:7010${NC}                    ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  Novu Dashboard    ${GREEN}http://localhost:7011${NC}                    ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  Novu WebSocket    ${GREEN}ws://localhost:7012${NC}                      ${CYAN}║${NC}"
if [ "$PHASE" -ge 2 ]; then
echo -e "${CYAN}║${NC}  DocuSeal          ${GREEN}http://localhost:7020${NC}                    ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  Lago API          ${GREEN}http://localhost:7030${NC}                    ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  Lago Dashboard    ${GREEN}http://localhost:7031${NC}                    ${CYAN}║${NC}"
fi
if [ "$PHASE" -ge 3 ]; then
echo -e "${CYAN}║${NC}  Twenty CRM        ${GREEN}http://localhost:7040${NC}                    ${CYAN}║${NC}"
fi
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
info "Run 'docker compose -f docker/docker-compose.yml ${PROFILES[*]} logs -f' to tail logs."
info "Run 'docker compose -f docker/docker-compose.yml ${PROFILES[*]} down' to stop."

#!/usr/bin/env bash
# =============================================================================
# Cypress Zero-Ops — Import n8n Workflows
# =============================================================================
# Imports all JSON workflow files from n8n-workflows/ into n8n.
# Usage: ./scripts/import-n8n.sh [directory]
#   directory: subfolder under n8n-workflows/ (default: all phase dirs)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

N8N_URL="${WEBHOOK_URL:-http://localhost:7678}"
N8N_USER="${N8N_BASIC_AUTH_USER:-admin}"
N8N_PASS="${N8N_BASIC_AUTH_PASSWORD:-cypress_n8n_dev}"

IMPORT_DIR="${1:-}"

if [ -n "$IMPORT_DIR" ]; then
  DIRS=("$ROOT_DIR/n8n-workflows/$IMPORT_DIR")
else
  DIRS=("$ROOT_DIR/n8n-workflows/phase-1" "$ROOT_DIR/n8n-workflows/phase-2" \
        "$ROOT_DIR/n8n-workflows/phase-3" "$ROOT_DIR/n8n-workflows/phase-4")
fi

echo "[INFO] Importing n8n workflows into $N8N_URL..."

IMPORTED=0
FAILED=0

for dir in "${DIRS[@]}"; do
  if [ ! -d "$dir" ]; then
    continue
  fi

  for file in "$dir"/*.json; do
    [ -f "$file" ] || continue
    FILENAME=$(basename "$file")
    echo -n "  Importing $FILENAME... "

    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
      -u "$N8N_USER:$N8N_PASS" \
      -X POST "$N8N_URL/api/v1/workflows" \
      -H "Content-Type: application/json" \
      -d @"$file")

    if [ "$RESPONSE" -ge 200 ] && [ "$RESPONSE" -lt 300 ]; then
      echo "OK ($RESPONSE)"
      IMPORTED=$((IMPORTED + 1))
    else
      echo "FAILED ($RESPONSE)"
      FAILED=$((FAILED + 1))
    fi
  done
done

echo ""
echo "[DONE] Imported: $IMPORTED, Failed: $FAILED"

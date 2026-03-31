#!/usr/bin/env bash
# =============================================================================
# Cypress Zero-Ops — Export n8n Workflows
# =============================================================================
# Exports all n8n workflows as JSON files for version control.
# Usage: ./scripts/export-n8n.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

N8N_URL="${WEBHOOK_URL:-http://localhost:7678}"
N8N_USER="${N8N_BASIC_AUTH_USER:-admin}"
N8N_PASS="${N8N_BASIC_AUTH_PASSWORD:-cypress_n8n_dev}"

EXPORT_DIR="$ROOT_DIR/n8n-workflows/exported"
mkdir -p "$EXPORT_DIR"

echo "[INFO] Exporting n8n workflows from $N8N_URL..."

# Fetch all workflows via n8n REST API
WORKFLOWS=$(curl -s -u "$N8N_USER:$N8N_PASS" "$N8N_URL/api/v1/workflows" \
  -H "Accept: application/json")

# Count workflows
COUNT=$(echo "$WORKFLOWS" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',[])))" 2>/dev/null || echo 0)

if [ "$COUNT" -eq 0 ]; then
  echo "[WARN] No workflows found to export."
  exit 0
fi

echo "[INFO] Found $COUNT workflow(s). Exporting..."

# Export each workflow individually
echo "$WORKFLOWS" | python3 -c "
import sys, json, os
data = json.load(sys.stdin).get('data', [])
export_dir = '$EXPORT_DIR'
for wf in data:
    name = wf.get('name', 'unnamed').replace(' ', '-').replace('/', '_').lower()
    wf_id = wf.get('id', 'unknown')
    filename = f'{name}_{wf_id}.json'
    filepath = os.path.join(export_dir, filename)
    with open(filepath, 'w') as f:
        json.dump(wf, f, indent=2)
    print(f'  Exported: {filename}')
"

echo "[OK] Workflows exported to n8n-workflows/exported/"

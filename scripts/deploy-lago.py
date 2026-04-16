#!/usr/bin/env python3
"""
Cypress Zero-Ops — Railway Deployment: Lago (Phase 2)
=====================================================
Deploys Lago billing & metering services to Railway:
  - lago-api       → Docker: getlago/api:v1.45.1 (API + healthcheck)
  - lago-worker    → Docker: getlago/api:v1.45.1 (background jobs)
  - lago-clock     → Docker: getlago/api:v1.45.1 (scheduler)
  - lago-front     → Docker: getlago/front:v1.45.1 (dashboard UI)

Prerequisites:
  - Phase 1 must be deployed (deploy-railway.py)
  - 'lago' logical database must exist in shared PostgreSQL
  - Redis must be running (Lago uses DB index 3)

Usage:
  python3 scripts/deploy-lago.py

The script is idempotent — re-running will skip existing services.
"""

import json
import os
import sys
import secrets
import urllib.request
import urllib.error
import time

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
RAILWAY_API = "https://backboard.railway.com/graphql/v2"
TOKEN = None

# Try reading from Railway CLI config
config_path = os.path.expanduser("~/.railway/config.json")
if os.path.exists(config_path):
    with open(config_path) as f:
        config = json.load(f)
    user = config.get("user", {})
    TOKEN = user.get("token") or user.get("accessToken")

TOKEN = os.environ.get("RAILWAY_TOKEN", TOKEN)

if not TOKEN:
    print("ERROR: Set RAILWAY_TOKEN env var or login via `railway login`")
    sys.exit(1)

# Same project as Phase 1
PROJECT_ID = "2fb361f4-f269-480b-be30-4e8e6eb15ae3"
ENV_NAME = "production"

# Secrets file from Phase 1 (to reuse PG credentials)
SECRETS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".railway-secrets.json")
LAGO_SECRETS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".railway-lago-secrets.json")

# Lago image version (pinned, matches docker-compose.yml)
LAGO_VERSION = "v1.45.1"

# ---------------------------------------------------------------------------
# GraphQL helpers
# ---------------------------------------------------------------------------
def gql(query: str, variables: dict = None) -> dict:
    payload = json.dumps({"query": query, "variables": variables or {}}).encode()
    req = urllib.request.Request(
        RAILWAY_API,
        data=payload,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json",
            "User-Agent": "railway-cli/4.36.1",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            result = json.loads(resp.read())
        if "errors" in result and not result.get("data"):
            print(f"  GraphQL errors: {json.dumps(result['errors'], indent=2)[:300]}")
        return result.get("data", result)
    except urllib.error.HTTPError as e:
        body = e.read().decode()[:300] if e.fp else ""
        print(f"  HTTP {e.code}: {body}")
        return {"errors": [{"message": f"HTTP {e.code}: {body}"}]}


def set_vars(svc_name: str, svc_id: str, variables: dict):
    """Set env vars on a service."""
    result = gql("""
    mutation($input: VariableCollectionUpsertInput!) {
        variableCollectionUpsert(input: $input)
    }
    """, {"input": {
        "projectId": PROJECT_ID,
        "environmentId": env_id,
        "serviceId": svc_id,
        "variables": variables,
    }})
    print(f"  {svc_name}: {len(variables)} vars set")


# ---------------------------------------------------------------------------
# Step 0: Verify project and get environment ID
# ---------------------------------------------------------------------------
print("\n=== Step 0: Project Verification ===")

project_data = gql("""
query($id: String!) {
    project(id: $id) {
        id
        name
        environments {
            edges { node { id name } }
        }
        services {
            edges { node { id name } }
        }
    }
}
""", {"id": PROJECT_ID})

proj = project_data.get("project")
if not proj:
    print("ERROR: Cannot access project. Check permissions.")
    sys.exit(1)

print(f"  Project: {proj['name']} ({PROJECT_ID})")

env_id = None
for edge in proj.get("environments", {}).get("edges", []):
    node = edge["node"]
    if node["name"] == ENV_NAME:
        env_id = node["id"]
        break

if not env_id:
    print(f"ERROR: No '{ENV_NAME}' environment found")
    sys.exit(1)

print(f"  Environment: {ENV_NAME} ({env_id})")

# Collect existing services
existing_services = {}
for edge in proj.get("services", {}).get("edges", []):
    node = edge["node"]
    existing_services[node["name"]] = node["id"]

print(f"  Existing services: {', '.join(existing_services.keys())}")

# Verify Phase 1 prerequisites
required = ["Postgres", "Redis"]
for req in required:
    if req not in existing_services:
        print(f"ERROR: Required service '{req}' not found. Run deploy-railway.py first.")
        sys.exit(1)

# ---------------------------------------------------------------------------
# Step 1: Load Phase 1 secrets (need PG password)
# ---------------------------------------------------------------------------
print("\n=== Step 1: Load Secrets ===")

if not os.path.exists(SECRETS_FILE):
    print(f"ERROR: {SECRETS_FILE} not found. Run deploy-railway.py first to generate Phase 1 secrets.")
    sys.exit(1)

with open(SECRETS_FILE) as f:
    phase1_secrets = json.load(f)

PG_USER = "cypress"
PG_PASS = phase1_secrets["POSTGRES_PASSWORD"]
PG_HOST = "postgres.railway.internal"
REDIS_HOST = "redis.railway.internal"

print(f"  Loaded Phase 1 secrets (PG user: {PG_USER})")

# Generate or load Lago-specific secrets
if os.path.exists(LAGO_SECRETS_FILE):
    with open(LAGO_SECRETS_FILE) as f:
        lago_secrets = json.load(f)
    print(f"  Loaded existing Lago secrets from {LAGO_SECRETS_FILE}")
else:
    lago_secrets = {
        "LAGO_SECRET_KEY_BASE": secrets.token_hex(32),
        "LAGO_ENCRYPTION_PRIMARY_KEY": secrets.token_hex(16),
        "LAGO_ENCRYPTION_DETERMINISTIC_KEY": secrets.token_hex(16),
        "LAGO_ENCRYPTION_KEY_DERIVATION_SALT": secrets.token_hex(16),
    }
    with open(LAGO_SECRETS_FILE, "w") as f:
        json.dump(lago_secrets, f, indent=2)
    os.chmod(LAGO_SECRETS_FILE, 0o600)
    print(f"  Generated and saved Lago secrets to {LAGO_SECRETS_FILE}")

# Read existing RSA private key from .env (used for webhook signing)
RSA_KEY = ""
env_file = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env")
if os.path.exists(env_file):
    with open(env_file) as f:
        for line in f:
            if line.startswith("LAGO_RSA_PRIVATE_KEY="):
                RSA_KEY = line.split("=", 1)[1].strip()
                break

if not RSA_KEY:
    # Generate a new RSA key (base64 encoded)
    import subprocess
    result = subprocess.run(
        ["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048"],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        import base64
        RSA_KEY = base64.b64encode(result.stdout.encode()).decode()
        print("  Generated new RSA private key")
    else:
        print("  WARNING: Could not generate RSA key. Lago webhook signing may not work.")

# ---------------------------------------------------------------------------
# Step 2: Create Lago services
# ---------------------------------------------------------------------------
print("\n=== Step 2: Create Lago Services ===")

LAGO_SERVICES = {
    "Lago-API": f"getlago/api:{LAGO_VERSION}",
    "Lago-Worker": f"getlago/api:{LAGO_VERSION}",
    "Lago-Clock": f"getlago/api:{LAGO_VERSION}",
    "Lago-Front": f"getlago/front:{LAGO_VERSION}",
}

lago_service_ids = {}
for name, image in LAGO_SERVICES.items():
    if name in existing_services:
        lago_service_ids[name] = existing_services[name]
        print(f"  Skip (exists): {name} ({existing_services[name]})")
        continue

    result = gql("""
    mutation($input: ServiceCreateInput!) {
        serviceCreate(input: $input) {
            id
            name
        }
    }
    """, {"input": {
        "name": name,
        "projectId": PROJECT_ID,
        "source": {"image": image},
    }})

    svc = result.get("serviceCreate")
    if svc:
        lago_service_ids[name] = svc["id"]
        print(f"  Created: {name} ({svc['id']})")
    else:
        print(f"  ERROR creating {name}: {result}")
        sys.exit(1)

    time.sleep(1)  # Rate limit

# ---------------------------------------------------------------------------
# Step 3: Set start commands (different entrypoints per service)
# ---------------------------------------------------------------------------
print("\n=== Step 3: Start Commands ===")

START_COMMANDS = {
    "Lago-API": "./scripts/start.api.sh",
    "Lago-Worker": "./scripts/start.worker.sh",
    "Lago-Clock": "./scripts/start.clock.sh",
    # Lago-Front uses default CMD from the image (nginx)
}

for name, cmd in START_COMMANDS.items():
    try:
        gql("""
        mutation($id: String!, $input: ServiceUpdateInput!) {
            serviceUpdate(id: $id, input: $input) { id }
        }
        """, {
            "id": lago_service_ids[name],
            "input": {"startCommand": cmd},
        })
        print(f"  {name}: {cmd}")
    except Exception as e:
        print(f"  {name}: error setting command: {e}")

# ---------------------------------------------------------------------------
# Step 4: Set environment variables
# ---------------------------------------------------------------------------
print("\n=== Step 4: Environment Variables ===")

# Shared Lago env vars (all backend services: API, Worker, Clock)
LAGO_DB_URL = f"postgres://{PG_USER}:{PG_PASS}@{PG_HOST}:5432/lago"
LAGO_REDIS_URL = f"redis://{REDIS_HOST}:6379/3"

LAGO_COMMON_VARS = {
    "DATABASE_URL": LAGO_DB_URL,
    "REDIS_URL": LAGO_REDIS_URL,
    "SECRET_KEY_BASE": lago_secrets["LAGO_SECRET_KEY_BASE"],
    "RAILS_ENV": "production",
    "LAGO_RSA_PRIVATE_KEY": RSA_KEY,
    "LAGO_ENCRYPTION_PRIMARY_KEY": lago_secrets["LAGO_ENCRYPTION_PRIMARY_KEY"],
    "LAGO_ENCRYPTION_DETERMINISTIC_KEY": lago_secrets["LAGO_ENCRYPTION_DETERMINISTIC_KEY"],
    "LAGO_ENCRYPTION_KEY_DERIVATION_SALT": lago_secrets["LAGO_ENCRYPTION_KEY_DERIVATION_SALT"],
    "LAGO_WEBHOOK_ATTEMPTS": "3",
    "LAGO_USE_AWS_S3": "false",
    "LAGO_DISABLE_SIGNUP": "true",
}

# Lago-API specific
set_vars("Lago-API", lago_service_ids["Lago-API"], {
    **LAGO_COMMON_VARS,
    "RAILS_LOG_TO_STDOUT": "true",
    # LAGO_API_URL and LAGO_FRONT_URL will be set after domain creation
})

# Lago-Worker
set_vars("Lago-Worker", lago_service_ids["Lago-Worker"], {
    **LAGO_COMMON_VARS,
})

# Lago-Clock
set_vars("Lago-Clock", lago_service_ids["Lago-Clock"], {
    **LAGO_COMMON_VARS,
})

# Lago-Front (no DB access, just needs API URL)
# LAGO_FRONT_URL env will be set after domain creation
set_vars("Lago-Front", lago_service_ids["Lago-Front"], {
    "APP_ENV": "production",
    "LAGO_DISABLE_SIGNUP": "true",
})

# ---------------------------------------------------------------------------
# Step 5: Create public domains for Lago-API and Lago-Front
# ---------------------------------------------------------------------------
print("\n=== Step 5: Public Domains ===")

public_domain_services = ["Lago-API", "Lago-Front"]
lago_public_domains = {}

for svc_name in public_domain_services:
    svc_id = lago_service_ids[svc_name]
    try:
        result = gql("""
        mutation($input: ServiceDomainCreateInput!) {
            serviceDomainCreate(input: $input) {
                domain
            }
        }
        """, {"input": {
            "serviceId": svc_id,
            "environmentId": env_id,
        }})
        if result and "serviceDomainCreate" in result:
            domain = result["serviceDomainCreate"]["domain"]
            lago_public_domains[svc_name] = domain
            print(f"  {svc_name}: https://{domain}")
        else:
            print(f"  {svc_name}: unexpected result: {result}")
    except Exception as e:
        print(f"  {svc_name}: error: {e}")
    time.sleep(1)

# ---------------------------------------------------------------------------
# Step 6: Set domain-dependent env vars
# ---------------------------------------------------------------------------
print("\n=== Step 6: Domain-Dependent Variables ===")

lago_api_url = f"https://{lago_public_domains.get('Lago-API', 'lago-api.railway.internal:3000')}"
lago_front_url = f"https://{lago_public_domains.get('Lago-Front', 'lago-front.railway.internal')}"

# Update Lago-API with its own URL + Front URL
set_vars("Lago-API", lago_service_ids["Lago-API"], {
    "LAGO_API_URL": lago_api_url,
    "LAGO_FRONT_URL": lago_front_url,
})

# Update Lago-Worker with API URL
set_vars("Lago-Worker", lago_service_ids["Lago-Worker"], {
    "LAGO_API_URL": lago_api_url,
})

# Update Lago-Clock with API URL
set_vars("Lago-Clock", lago_service_ids["Lago-Clock"], {
    "LAGO_API_URL": lago_api_url,
})

# Update Lago-Front with API URL
set_vars("Lago-Front", lago_service_ids["Lago-Front"], {
    "API_URL": lago_api_url,
    "LAGO_OAUTH_PROXY_URL": "",
})

# ---------------------------------------------------------------------------
# Step 7: Create 'lago' database in shared PostgreSQL
# ---------------------------------------------------------------------------
print("\n=== Step 7: Database Setup ===")
print("  NOTE: The 'lago' database must exist in the shared PostgreSQL instance.")
print("  If it doesn't exist yet, connect to Postgres and run:")
print(f"    CREATE DATABASE lago;")
print("  Lago will auto-migrate its schema on first API start.")

# ---------------------------------------------------------------------------
# Step 8: Summary
# ---------------------------------------------------------------------------
print("\n" + "=" * 60)
print("  LAGO DEPLOYMENT SUMMARY")
print("=" * 60)
print(f"\n  Project:     {PROJECT_ID}")
print(f"  Environment: {ENV_NAME} ({env_id})")
print(f"  Version:     {LAGO_VERSION}")

print(f"\n  Services:")
for name, sid in lago_service_ids.items():
    domain = lago_public_domains.get(name, "(internal)")
    print(f"    {name:15} {sid}  {domain}")

print(f"\n  Lago-API URL:   {lago_api_url}")
print(f"  Lago-Front URL: {lago_front_url}")

print(f"\n  Database:  {LAGO_DB_URL.replace(PG_PASS, '***')}")
print(f"  Redis:     {LAGO_REDIS_URL}")

print(f"\n  Secrets saved to: {LAGO_SECRETS_FILE}")

print(f"\n" + "=" * 60)
print("  NEXT STEPS")
print("=" * 60)
print(f"""
  1. Wait for all 4 Lago services to deploy in Railway dashboard
  2. Create 'lago' database if it doesn't exist:
     Connect to Railway Postgres and run: CREATE DATABASE lago;
  3. Lago-API will auto-run migrations on first start
  4. Access Lago dashboard at: {lago_front_url}
  5. Create an admin account (first signup creates admin)
  6. Create custom staging domains:
     python3 scripts/setup-domains.py
     → billing.staging.getcypress.xyz     (Lago-Front)
     → billing-api.staging.getcypress.xyz (Lago-API)
  7. Configure Lago:
     a. Create billable metrics (vehicles_appraised, vehicles_sold, etc.)
     b. Create plans (sandbox, pro)
     c. Set webhook endpoint: https://staging.app.getcypress.xyz/api/webhooks/lago
  8. Get Lago API key from dashboard → set in cypress-mvp Railway env vars:
     LAGO_API_URL={lago_api_url}
     LAGO_API_KEY=<from Lago dashboard>
     LAGO_WEBHOOK_SECRET=<from Lago dashboard>
""")

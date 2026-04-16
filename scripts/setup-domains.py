#!/usr/bin/env python3
"""Create custom staging domains for both Railway projects."""
import json, urllib.request, sys, time

with open("/Users/andrespetrillo/.railway/config.json") as f:
    c = json.load(f)
TOKEN = c["user"]["accessToken"]

def gql(query, variables=None):
    body = {"query": query}
    if variables: body["variables"] = variables
    payload = json.dumps(body).encode()
    req = urllib.request.Request("https://backboard.railway.com/graphql/v2", data=payload,
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json", "User-Agent": "railway-cli/4.36.1"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body_text = e.read().decode() if e.fp else ""
        return {"errors": [{"message": f"HTTP {e.code}: {body_text[:300]}"}]}
    except Exception as e:
        return {"errors": [{"message": str(e)}]}

# ─── Zero-Ops Project ────────────────────────────────────────────
ZOPS_PROJECT = "2fb361f4-f269-480b-be30-4e8e6eb15ae3"
ZOPS_ENV = "9fa755a0-8c58-4032-9252-9cc05ac2123a"

# ─── cypress-mvp Project ─────────────────────────────────────────
MVP_PROJECT = "78394b79-28bd-4da0-b3bf-87190b89a2b1"
MVP_ENV = "a4905c25-2f44-44da-a2db-e1e097d69482"

# Domain assignments
DOMAINS = [
    # Zero-Ops
    {"domain": "auth.staging.getcypress.xyz",          "serviceId": "f4670041-ce33-4c57-abca-fa07a9eb8470", "project": ZOPS_PROJECT, "env": ZOPS_ENV, "targetPort": 3001, "label": "Logto (API)"},
    {"domain": "auth-admin.staging.getcypress.xyz",    "serviceId": "f4670041-ce33-4c57-abca-fa07a9eb8470", "project": ZOPS_PROJECT, "env": ZOPS_ENV, "targetPort": 3002, "label": "Logto (Admin)"},
    {"domain": "workflows.staging.getcypress.xyz",     "serviceId": "5ba8c328-a4b1-4645-92af-407ba0fc0cbc", "project": ZOPS_PROJECT, "env": ZOPS_ENV, "targetPort": 5678, "label": "n8n"},
    {"domain": "notifications.staging.getcypress.xyz", "serviceId": "9aaea8dd-8611-47ce-b16a-51d1c8a1f619", "project": ZOPS_PROJECT, "env": ZOPS_ENV, "targetPort": None, "label": "Novu-Web"},
    {"domain": "ws.staging.getcypress.xyz",            "serviceId": "2890e2bb-f688-4ef2-9cd1-5deba4496aa9", "project": ZOPS_PROJECT, "env": ZOPS_ENV, "targetPort": None, "label": "Novu-WS"},
    {"domain": "bi.staging.getcypress.xyz",            "serviceId": "d3d77d84-af18-434d-bd51-4a68864ff4f7", "project": ZOPS_PROJECT, "env": ZOPS_ENV, "targetPort": 3000, "label": "Metabase"},
    # Lago (Phase 2)
    {"domain": "billing.staging.getcypress.xyz",      "serviceId": "4792098a-840f-410d-a4a2-2616a56fecd1", "project": ZOPS_PROJECT, "env": ZOPS_ENV, "targetPort": 80,   "label": "Lago-Front"},
    {"domain": "billing-api.staging.getcypress.xyz",  "serviceId": "2d3316c7-d063-46d7-9267-68162d94c77d", "project": ZOPS_PROJECT, "env": ZOPS_ENV, "targetPort": 3000, "label": "Lago-API"},
    # cypress-mvp
    {"domain": "app.staging.getcypress.xyz",           "serviceId": "de751dcc-2498-4c3e-9a77-7a3ebc52e967", "project": MVP_PROJECT, "env": MVP_ENV, "targetPort": None, "label": "Web (cypress-mvp)"},
    {"domain": "inspect.staging.getcypress.xyz",       "serviceId": "705bcc19-dfe4-4a83-aa2c-2d21acc5e3a9", "project": MVP_PROJECT, "env": MVP_ENV, "targetPort": 6101, "label": "ARVIS"},
    {"domain": "data.staging.getcypress.xyz",          "serviceId": "3ed9eab9-f5bb-479f-b97b-d6314e5f0a0e", "project": MVP_PROJECT, "env": MVP_ENV, "targetPort": 6102, "label": "Orbis"},
]

print("=" * 60)
print("Creating custom staging domains")
print("=" * 60)

cname_records = []

for d in DOMAINS:
    print(f"\n  {d['label']}: {d['domain']}")
    
    variables = {
        "input": {
            "domain": d["domain"],
            "environmentId": d["env"],
            "projectId": d["project"],
            "serviceId": d["serviceId"],
        }
    }
    if d["targetPort"]:
        variables["input"]["targetPort"] = d["targetPort"]
    
    result = gql("""
    mutation($input: CustomDomainCreateInput!) {
        customDomainCreate(input: $input) {
            id
            domain
            status {
                dnsRecords {
                    requiredValue
                    currentValue
                    hostlabel
                    zone
                    purpose
                    fqdn
                }
            }
        }
    }
    """, variables)
    
    if "errors" in result:
        err = str(result["errors"])
        if "already" in err.lower() or "exists" in err.lower() or "duplicate" in err.lower():
            print(f"    Already exists")
        else:
            print(f"    Error: {result['errors'][0].get('message', err)[:200]}")
    else:
        cd = result.get("data", {}).get("customDomainCreate", {})
        if cd:
            print(f"    Created: {cd.get('id', '?')[:12]}...")
            dns = cd.get("status", {}).get("dnsRecords", [])
            for rec in dns:
                fqdn = rec.get("fqdn", d["domain"])
                value = rec.get("requiredValue", "?")
                purpose = rec.get("purpose", "?")
                cname_records.append({"domain": fqdn, "value": value, "purpose": purpose, "label": d["label"]})
                print(f"    DNS: {fqdn} -> {value} ({purpose})")
    
    time.sleep(1)

# ─── Summary: CNAME records needed ──────────────────────────────
print("\n" + "=" * 60)
print("CNAME RECORDS NEEDED IN CLOUDFLARE")
print("=" * 60)
print("\nAdd these CNAME records in Cloudflare DNS for getcypress.xyz:\n")
print(f"{'Subdomain':<45} {'Target':<50} {'Service'}")
print("-" * 130)
for r in cname_records:
    subdomain = r["domain"].replace(".getcypress.xyz", "")
    print(f"{subdomain:<45} {r['value']:<50} {r['label']}")

print("\nNote: Set Cloudflare proxy to 'DNS only' (gray cloud) for Railway SSL to work.")
print("\nDone.")

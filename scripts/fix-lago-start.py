#!/usr/bin/env python3
"""Fix Lago start commands on Railway."""
import json, urllib.request

with open("/Users/andrespetrillo/.railway/config.json") as f:
    c = json.load(f)
TOKEN = c["user"]["accessToken"]

PROJECT_ID = "2fb361f4-f269-480b-be30-4e8e6eb15ae3"
ENV_ID = "9fa755a0-8c58-4032-9252-9cc05ac2123a"

def gql(query, variables=None):
    payload = json.dumps({"query": query, "variables": variables or {}}).encode()
    req = urllib.request.Request("https://backboard.railway.com/graphql/v2", data=payload,
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json",
                 "User-Agent": "railway-cli/4.36.1"})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())

services = {
    "Lago-API":    ("2d3316c7-d063-46d7-9267-68162d94c77d", "./scripts/start.api.sh"),
    "Lago-Worker": ("08c28b76-9844-4c50-a8bd-186f9a9c0355", "./scripts/start.worker.sh"),
    "Lago-Clock":  ("bbd1c5c6-30cf-491c-8659-8fbe4befb670", "./scripts/start.clock.sh"),
}

for name, (sid, cmd) in services.items():
    # Set via serviceInstanceUpdate which is the correct mutation for Docker image services
    # Set Docker CMD override via env var (Railway reads this for start command)
    result = gql("""
    mutation($input: VariableCollectionUpsertInput!) {
        variableCollectionUpsert(input: $input)
    }
    """, {"input": {
        "projectId": PROJECT_ID,
        "environmentId": ENV_ID,
        "serviceId": sid,
        "variables": {"RAILWAY_DOCKERFILE_CMD": cmd},
    }})
    print(f"  {name}: RAILWAY_DOCKERFILE_CMD={cmd} -> {result}")

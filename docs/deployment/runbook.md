# Operational Runbook

Procedures for common operational tasks and incident response.

## Service Health Checks

### Quick Status

```bash
# All running containers
docker compose -f docker/docker-compose.yml --profile phase1 --profile phase2 --profile phase3 ps

# Service-specific health
docker inspect cypress-postgres --format='{{.State.Health.Status}}'
docker inspect cypress-redis --format='{{.State.Health.Status}}'
```

### Service Endpoints

| Service | Health Endpoint | Expected |
|---------|----------------|----------|
| PostgreSQL | `pg_isready -h localhost -p 7432 -U cypress` | Exit 0 |
| Redis | `redis-cli -h localhost -p 7379 ping` | `PONG` |
| Logto | `curl http://localhost:7001/oidc/.well-known/openid-configuration` | JSON response |
| n8n | `curl http://localhost:7678/healthz` | `{"status":"ok"}` |
| Novu API | `curl http://localhost:7010/v1/health-check` | 200 |
| DocuSeal | `curl http://localhost:7020` | 200 |
| Lago API | `curl http://localhost:7030/api/v1/health` | 200 |
| Twenty | `curl http://localhost:7040/api` | 200 |

## Common Operations

### Restart a Single Service

```bash
docker compose -f docker/docker-compose.yml --profile phase1 restart logto
```

### View Logs

```bash
# Tail all services
docker compose -f docker/docker-compose.yml --profile phase1 logs -f

# Specific service, last 100 lines
docker compose -f docker/docker-compose.yml --profile phase1 logs --tail 100 logto
```

### Update Service Images

```bash
# Pull latest images
docker compose -f docker/docker-compose.yml --profile phase1 pull

# Recreate with new images
docker compose -f docker/docker-compose.yml --profile phase1 up -d --force-recreate
```

### Database Access

```bash
# Shared PostgreSQL
docker exec -it cypress-postgres psql -U cypress -d logto

# Lago PostgreSQL
docker exec -it cypress-lago-db psql -U lago -d lago

# List all databases
docker exec -it cypress-postgres psql -U cypress -c '\l'
```

### Export n8n Workflows

```bash
./scripts/export-n8n.sh
# Workflows saved to n8n-workflows/exported/
# Commit these to Git for version control
```

### Import n8n Workflows

```bash
# Import all phases
./scripts/import-n8n.sh

# Import specific phase
./scripts/import-n8n.sh phase-1
```

## Incident Procedures

### Payment Failed (Phase 4)

1. **Check Stripe dashboard** for payment failure reason
2. **Check n8n execution history** at http://localhost:7678 → Executions
3. **Check Lago webhook delivery** at http://localhost:7031 → Webhooks
4. **If retry needed**: Re-trigger the Lago invoice finalization
5. **Notify customer**: Novu should have sent automatic failure notification
6. **Escalate**: If systemic, check Stripe status page

### Logto Auth Down

1. **Check Logto logs**: `docker logs cypress-logto --tail 100`
2. **Check PostgreSQL**: `docker exec cypress-postgres pg_isready -U cypress`
3. **Common fix**: Restart Logto: `docker restart cypress-logto`
4. **Impact**: Users cannot log in, but existing JWT tokens remain valid until expiry
5. **Cypress Core**: Should handle Logto unavailability gracefully (cache JWKS)

### n8n Workflow Failures

1. **Open n8n dashboard** at http://localhost:7678
2. **Navigate to Executions** → filter by "Error"
3. **Check the failed node** — n8n shows the exact request/response
4. **Common causes**:
   - Service temporarily unavailable → retry the execution
   - Invalid credentials → update in n8n Credentials
   - Payload format changed → update the workflow
5. **Manual retry**: Click "Retry" on the failed execution

### Lago Billing Discrepancy

1. **Compare sources**:
   - Lago: http://localhost:7031 → Invoices
   - Stripe: https://dashboard.stripe.com/payments
   - QuickBooks: QB dashboard
2. **Run reconciliation workflow** in n8n (scheduled monthly)
3. **Common causes**:
   - Webhook delivery failure → check n8n execution history
   - Duplicate events → check Lago event `transaction_id` uniqueness
   - Timing: invoice created but payment not yet processed

### Service Won't Start

```bash
# Check container exit code and logs
docker compose -f docker/docker-compose.yml --profile phase1 ps -a
docker logs cypress-<service> --tail 50

# Common issues:
# 1. Port conflict: lsof -i :<port>
# 2. Volume permissions: docker volume inspect cypress-zero-ops_<volume>
# 3. Database not ready: check depends_on health conditions
# 4. Missing env vars: compare .env with .env.example
```

### Full Stack Reset (Development Only)

**Warning: This destroys all data.**

```bash
docker compose -f docker/docker-compose.yml \
  --profile phase1 --profile phase2 --profile phase3 \
  down -v --remove-orphans

# Restart clean
./scripts/setup.sh
```

## Monitoring Checklist (Production)

- [ ] Railway resource alerts configured (CPU > 80%, memory > 80%)
- [ ] n8n error notification workflow active (sends to Slack on any workflow failure)
- [ ] Lago webhook delivery monitoring enabled
- [ ] Stripe webhook endpoint health monitored
- [ ] PostgreSQL connection count monitored
- [ ] Redis memory usage monitored
- [ ] Daily database backup verification
- [ ] Monthly reconciliation workflow running

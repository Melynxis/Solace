# Executive Implementation Summary — Solace Core (MySQL/Redis/Weaviate)

**Date:** 2025-09-02  
**Host:** `solace` (Ubuntu 24.04 LTS)  
**Scope:** Bring Solace core services up reliably; fix Weaviate readiness/auth; document stable runbook.

---

## 1) Objective
Restore a stable single-node Weaviate with API-key auth, alongside healthy MySQL and Redis, and capture a repeatable operational procedure.

---

## 2) Final State (✅ working)
- **MySQL**: container healthy; root + `solace_app` verified; grants ensured for DB `solace`.
- **Redis**: container healthy; local ping OK via `docker exec … redis-cli`.
- **Weaviate**: container healthy; readiness `200`; **schema access works with `Authorization: Bearer <WEAVIATE_APIKEY>`**; `X-API-KEY` may 401 (expected for this build).
- **Auth model**: Anonymous **disabled**, API-key **enabled**.
- **Raft/cluster**: operating as a single leader on `node1`; previous “join loop” eliminated by wiping stale raft state/volume during clean reinstall.

---

## 3) Key Actions Performed
1. **Core bring-up & DB grants**
   - Verified MySQL root login and ensured `GRANT` for `solace_app`@`%` against `solace`.
   - Confirmed Redis health from inside container.
2. **Weaviate repair (multiple iterations)**
   - Addressed raft join loops by wiping `raft/` and related on-disk state when needed.
   - Added a temporary `compose.weaviate.override.yml` for clean single-node bootstrap.
   - Reinstalled Weaviate cleanly (backed up `/var/lib/weaviate` first; removed stale docker volume; recreated bind/volume).
   - Ensured auth env was visible **inside** the container.
   - Proved readiness from **both** host and inside-container to bypass host networking gotchas.
3. **Auth consistency**
   - `.env` includes:
     - `WEAVIATE_APIKEY=REDACTED`
     - `WEAVIATE_AUTHENTICATION_APIKEY_ENABLED=true`
     - `WEAVIATE_AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=false`
   - Confirmed container env:
     - `AUTHENTICATION_APIKEY_ALLOWED_KEYS=<same as .env>`
     - `AUTHENTICATION_APIKEY_ENABLED=true`
     - `AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=false`
   - Observed that this Weaviate build expects **Bearer** form; `X-API-KEY` may return `401`. Bearer works and is the supported path.

---

## 4) How to Operate (Runbook)

### Start/stop only Weaviate
```bash
cd /home/melynxis/solace/infra
docker compose --env-file /home/melynxis/solace/.env -f compose.core.yml up -d weaviate
docker compose -f compose.core.yml stop weaviate

# readiness
curl -fsS http://127.0.0.1:8080/v1/.well-known/ready | jq .

# schema (Bearer REQUIRED on this build)
curl -fsS -H "Authorization: Bearer $WEAVIATE_APIKEY" \
  http://127.0.0.1:8080/v1/schema | jq .


Known-good auth header (use this)

Authorization: Bearer <WEAVIATE_APIKEY>

Note: X-API-KEY: <WEAVIATE_APIKEY> may return 401 on this Weaviate release — that’s expected.

MYSQL_DB=solace
MYSQL_USER=solace_app
MYSQL_PASSWORD=REDACTED
MYSQL_ROOT_PASSWORD=REDACTED

REDIS_PASSWORD=REDACTED
REDIS_URL=redis://:REDACTED@127.0.0.1:6379

WEAVIATE_APIKEY=REDACTED
WEAVIATE_AUTHENTICATION_APIKEY_ENABLED=true
WEAVIATE_AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=false



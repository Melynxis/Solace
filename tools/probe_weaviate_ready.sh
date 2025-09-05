#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/home/melynxis/solace/.env"
if [ -f "$ENV_FILE" ]; then set -a; . "$ENV_FILE"; set +a; fi

BASE="http://127.0.0.1:8080"
KEY="${WEAVIATE_APIKEY:-}"

echo "==> Probing Weaviate readiness (auth enabled, anon disabled)"
echo "   Using BASE=$BASE"
[ -n "$KEY" ] || { echo "   WARNING: WEAVIATE_APIKEY is empty in host env"; }

# Helper to show HTTP status
status() { curl -s -o /dev/null -w "%{http_code}" "$@"; }

noauth_ready=$(status "$BASE/v1/.well-known/ready")
auth_ready=$(status -H "X-API-KEY: $KEY" "$BASE/v1/.well-known/ready" || true)

echo "   /ready (no header) -> $noauth_ready"
echo "   /ready (X-API-KEY) -> $auth_ready"

if [ "$auth_ready" = "200" ]; then
  echo "✅ /ready authorized check passed."
else
  echo "❌ /ready with key not 200."
fi

# Try an authenticated API call that should require auth
schema_status=$(status -H "X-API-KEY: $KEY" "$BASE/v1/schema" || true)
echo "   /schema (X-API-KEY) -> $schema_status"

if [ "$schema_status" = "200" ]; then
  echo "✅ Authenticated API works."
else
  echo "❌ /schema not 200 with key; dumping a short error for context:"
  curl -fsS -H "X-API-KEY: $KEY" "$BASE/v1/schema" || true
fi

# If /ready still flaky from host, confirm inside the container (bypasses host net)
echo "==> In-container /ready check (should be 200):"
docker exec solace_weaviate sh -lc '
  apk add --no-cache curl >/dev/null 2>&1 || true
  curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/v1/.well-known/ready
'

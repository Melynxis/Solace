#!/usr/bin/env bash
# Restart Weaviate, wait for readiness, then test /schema with Bearer auth.
# Uses /home/melynxis/solace/.env

set -euo pipefail

INFRA_DIR="/home/melynxis/solace/infra"
ENV_FILE="/home/melynxis/solace/.env"
BASE="http://127.0.0.1:8080/v1"

echo "==> Loading env from $ENV_FILE"
set -a
. "$ENV_FILE"
set +a

echo "==> Restarting Weaviate (Compose + env-file)…"
docker compose --env-file "$ENV_FILE" -f "$INFRA_DIR/compose.core.yml" up -d weaviate

echo "==> Waiting for /ready (up to 90s)…"
for i in $(seq 1 90); do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/.well-known/ready" || true)
  if [ "$code" = "200" ]; then
    echo "   ready after ${i}s"
    break
  fi
  sleep 1
  if [ "$i" -eq 90 ]; then
    echo "❌ never reached /ready; recent logs:" >&2
    docker logs --tail=200 solace_weaviate >&2 || true
    exit 1
  fi
done

echo
echo "==> Verifying container-side auth env (sanity):"
docker exec solace_weaviate /bin/sh -lc 'env | egrep -i "^AUTHENTICATION_|^WEAVIATE_AUTH" || true' || true

echo
echo "==> Query /schema with Bearer auth…"
set +e
RESP=$(curl -s -H "Authorization: Bearer $WEAVIATE_APIKEY" "$BASE/schema")
RC=$?
set -e

if [ $RC -ne 0 ]; then
  echo "❌ curl error ($RC). Tail logs:" >&2
  docker logs --tail=200 solace_weaviate >&2 || true
  exit $RC
fi

# Pretty-print when jq is present
if command -v jq >/dev/null 2>&1; then
  echo "$RESP" | jq .
else
  echo "$RESP"
fi

echo "✅ Done."

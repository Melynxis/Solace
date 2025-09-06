#!/bin/bash
set -euo pipefail

ENV_FILE="/home/melynxis/solace/.env"
INFRA_DIR="/home/melynxis/solace/infra"

echo "==> Using env file: $ENV_FILE"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found."; exit 1
fi

echo "==> Restarting Weaviate with override + env-file"
cd "$INFRA_DIR"
docker compose --env-file "$ENV_FILE" \
  -f compose.core.yml \
  -f compose.weaviate.override.yml \
  up -d weaviate

echo "==> Verifying Weaviate env (inside container)"
docker exec solace_weaviate /bin/sh -lc 'env | egrep -i "AUTH|API|WEAVIATE|ANON|KEY" || true'

echo "==> Checking readiness (up to 60s) with and without API key..."
APIKEY="$(grep -E '^WEAVIATE_APIKEY=' "$ENV_FILE" | sed "s/WEAVIATE_APIKEY=//")"
for i in $(seq 1 20); do
  code1=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/v1/.well-known/ready)
  code2=$(curl -s -o /dev/null -w "%{http_code}" -H "X-API-KEY: $APIKEY" http://127.0.0.1:8080/v1/.well-known/ready)
  code3=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $APIKEY" http://127.0.0.1:8080/v1/.well-known/ready)
  echo "  try #$i: no-auth=$code1 x-api-key=$code2 bearer=$code3"
  if [ "$code1" = "200" ] || [ "$code2" = "200" ] || [ "$code3" = "200" ]; then
    echo "✅ Weaviate readiness OK"
    break
  fi
  sleep 3
done

echo "==> Quick schema access test (may require auth)"
echo "  -> /v1/schema with X-API-KEY"
curl -fsS -H "X-API-KEY: $APIKEY" http://127.0.0.1:8080/v1/schema | jq . || true

echo "  -> /v1/schema with Authorization: Bearer"
curl -fsS -H "Authorization: Bearer $APIKEY" http://127.0.0.1:8080/v1/schema | jq . || true

echo "==> If requests are 401:"
echo "   - Check container env above for:"
echo "       AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=false"
echo "       AUTHENTICATION_APIKEY_ENABLED=true"
echo "       AUTHENTICATION_APIKEY_ALLOWED_KEYS (or equivalent)"
echo "   - If missing, we need to add these to compose.weaviate.override.yml and re-up."

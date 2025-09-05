#!/usr/bin/env bash
set -euo pipefail

INFRA="/home/melynxis/solace/infra"
ENVF="/home/melynxis/solace/.env"

echo "==> Restarting Weaviate (core + override, with .env)…"
docker compose --env-file "$ENVF" \
  -f "$INFRA/compose.core.yml" \
  -f "$INFRA/compose.weaviate.override.yml" \
  up -d weaviate

echo "==> Waiting for /ready (up to 60s)…"
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/v1/.well-known/ready || true)
  echo "  try #$i: /ready -> $code"
  [ "$code" = "200" ] && break
  sleep 1
done
[ "$code" = "200" ] || { echo "❌ never reached /ready"; exit 1; }

echo "==> /schema using X-API-KEY (expected 200)"
curl -fsS -H "X-API-KEY: ${WEAVIATE_APIKEY:-}" http://127.0.0.1:8080/v1/schema | jq .

echo "==> /schema using Bearer (likely 401 on this build, that’s OK)"
set +e
curl -fsS -H "Authorization: Bearer ${WEAVIATE_APIKEY:-}" http://127.0.0.1:8080/v1/schema | jq .
set -e

#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/melynxis/solace"
INFRA="$ROOT/infra"
ENV_FILE="$ROOT/.env"
OVERRIDE="$INFRA/compose.weaviate.override.yml"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE missing"; exit 1
fi

# Load env (for WEAVIATE_APIKEY, etc.)
set -a; . "$ENV_FILE"; set +a

# --- 1) Write a strict single-node override (idempotent) ---
cat > "$OVERRIDE" <<'YAML'
services:
  weaviate:
    environment:
      # Storage & single-node cluster identity
      PERSISTENCE_DATA_PATH: /var/lib/weaviate
      CLUSTER_HOSTNAME: node1

      # Disable anonymous; enable API-key auth
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: "false"
      AUTHENTICATION_APIKEY_ENABLED: "true"
      AUTHENTICATION_APIKEY_ALLOWED_KEYS: ${WEAVIATE_APIKEY}
      AUTHENTICATION_APIKEY_USERS: solace

      # Keep vectorizer off (your config)
      DEFAULT_VECTORIZER_MODULE: none

      # Health timings (defaults are fine; leave for clarity)
      # PROMETHEUS_MONITORING_ENABLED: "true"
YAML

echo "==> Restarting Weaviate with override"
cd "$INFRA"
docker compose -f compose.core.yml -f compose.weaviate.override.yml up -d weaviate

# --- 2) Probe readiness, with and without API key (some builds enforce it on /ready) ---
ready_noauth() { curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/v1/.well-known/ready || true; }
ready_withkey() { curl -s -H "X-API-KEY: ${WEAVIATE_APIKEY:-}" -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/v1/.well-known/ready || true; }

echo "==> Checking Weaviate readiness (up to 45s)…"
ok=""
for i in $(seq 1 45); do
  code_key="$(ready_withkey)"
  code_na="$(ready_noauth)"
  echo "   try #$i: /ready no-auth=$code_na with-key=$code_key"
  if [[ "$code_key" == "200" || "$code_na" == "200" ]]; then ok="yes"; break; fi
  sleep 1
done

if [[ -z "$ok" ]]; then
  echo "!! Still not ready; clearing **only** stale Raft state and retrying"
  docker stop solace_weaviate >/dev/null
  # Keep data (objects/schema); wipe Raft cluster state only
  docker run --rm -v solace-core_weaviate_data:/store alpine \
    sh -lc 'rm -rf /store/raft || true; mkdir -p /store/raft'
  docker compose -f compose.core.yml -f compose.weaviate.override.yml up -d weaviate

  echo "==> Re-checking readiness (up to 45s)…"
  for i in $(seq 1 45); do
    code_key="$(ready_withkey)"
    code_na="$(ready_noauth)"
    echo "   try #$i: /ready no-auth=$code_na with-key=$code_key"
    if [[ "$code_key" == "200" || "$code_na" == "200" ]]; then ok="yes"; break; fi
    sleep 1
  done
fi

if [[ -z "$ok" ]]; then
  echo "❌ Weaviate still not ready. Last 120 log lines:"
  docker logs --tail=120 solace_weaviate
  exit 2
fi

echo "✅ Weaviate is READY."

# --- 3) Show quick, authenticated sanity calls you can use anytime ---
echo
echo "Try these:"
echo "  curl -fsS -H \"X-API-KEY: \$WEAVIATE_APIKEY\" http://127.0.0.1:8080/v1/.well-known/ready | jq ."
echo "  curl -fsS -H \"X-API-KEY: \$WEAVIATE_APIKEY\" http://127.0.0.1:8080/v1/schema | jq ."

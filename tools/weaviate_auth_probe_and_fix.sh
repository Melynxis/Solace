#!/usr/bin/env bash
set -euo pipefail

ENV_DIR="/home/melynxis/solace"
INFRA_DIR="/home/melynxis/solace/infra"
WEAV_CONT="solace_weaviate"

red()  { printf "\033[31m%s\033[0m\n" "$*"; }
grn()  { printf "\033[32m%s\033[0m\n" "$*"; }
ylw()  { printf "\033[33m%s\033[0m\n" "$*"; }
info() { printf "\n\033[36m==> %s\033[0m\n" "$*"; }

# Load .env
set -a
. "$ENV_DIR/.env"
set +a

BASE="http://127.0.0.1:8080"
KEY="${WEAVIATE_APIKEY:-}"

info "Key sanity (host)"
printf "  length: %s\n" "${#KEY}"
printf "  bytes :\n"
python3 - <<PY
import os, sys, binascii
k = os.environ.get("WEAVIATE_APIKEY","")
print(binascii.hexlify(k.encode()).decode())
PY

# Show container-side env
info "Container-side auth env"
docker exec "$WEAV_CONT" /bin/sh -lc 'env | grep -E "^AUTHENTICATION_|^PERSISTENCE_|^CLUSTER_" || true'

# Quick readiness (some setups keep /ready public even when anon=off)
info "/ready checks"
curl -s -o /dev/null -w "  host /ready -> %{http_code}\n" "$BASE/v1/.well-known/ready" || true
curl -s -o /dev/null -w "  host /ready (X-API-KEY) -> %{http_code}\n" -H "X-API-KEY: $KEY" "$BASE/v1/.well-known/ready" || true

# Try schema with several header spellings that Weaviate accepts
try_schema () {
  hdr="$1"
  code=$(curl -s -o /tmp/wv_body.$$ -w "%{http_code}" $hdr "$BASE/v1/schema" || true)
  printf "  /schema with %s -> %s\n" "$2" "$code"
  if [ "$code" != "200" ]; then
    head -c 160 /tmp/wv_body.$$ | sed 's/.*/    body: &/'; echo
  fi
  rm -f /tmp/wv_body.$$
}

info "/schema auth attempts"
try_schema "-H 'X-API-KEY: $KEY'"                   "X-API-KEY"
try_schema "-H 'Authorization: Bearer $KEY'"        "Authorization: Bearer"
try_schema "-H 'x-api-key: $KEY'"                   "x-api-key (lowercase)"

# In-container test to bypass any host/network oddities
info "In-container curl /schema"
docker exec "$WEAV_CONT" /bin/sh -lc "
  if ! command -v curl >/dev/null 2>&1; then apk add --no-cache curl >/dev/null 2>&1 || true; fi
  echo -n '  container /schema (X-API-KEY) -> '
  curl -s -o /tmp/b -w '%{http_code}\n' -H 'X-API-KEY: $KEY' http://127.0.0.1:8080/v1/schema
  echo -n '  container /schema (Bearer)    -> '
  curl -s -o /tmp/b -w '%{http_code}\n' -H 'Authorization: Bearer $KEY' http://127.0.0.1:8080/v1/schema
" || true

# If we still see 401, offer two surgical options:
# A) temporarily enable anon to prove auth is the only blocker, then disable again
# B) run with minimal override that drops USERS mapping (some builds are picky about it)

if ! curl -fsS -H "X-API-KEY: $KEY" "$BASE/v1/schema" >/dev/null 2>&1; then
  ylw "Auth still failing. Offering quick toggles."

  # A) Temporary anon-on probe
  TOGGLE_FILE="$INFRA_DIR/compose.weaviate.auth-toggle.yml"
  cat > "$TOGGLE_FILE" <<'YAML'
services:
  weaviate:
    environment:
      AUTHENTICATION_APIKEY_ENABLED: "true"
      AUTHENTICATION_APIKEY_ALLOWED_KEYS: ${WEAVIATE_APIKEY}
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: "true"
YAML

  info "Starting temporary anon=TRUE to confirm API works otherwise (will revert after probe)"
  docker compose --env-file "$ENV_DIR/.env" -f "$INFRA_DIR/compose.core.yml" -f "$TOGGLE_FILE" up -d weaviate

  # Wait a bit
  for i in $(seq 1 20); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/v1/.well-known/ready")
    [ "$code" = "200" ] && break
    sleep 1
  done

  printf "  anon-on /schema (no header) -> "
  curl -s -o /dev/null -w "%{http_code}\n" "$BASE/v1/schema" || true

  info "Reverting anon=FALSE"
  cat > "$TOGGLE_FILE" <<'YAML'
services:
  weaviate:
    environment:
      AUTHENTICATION_APIKEY_ENABLED: "true"
      AUTHENTICATION_APIKEY_ALLOWED_KEYS: ${WEAVIATE_APIKEY}
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: "false"
YAML
  docker compose --env-file "$ENV_DIR/.env" -f "$INFRA_DIR/compose.core.yml" -f "$TOGGLE_FILE" up -d weaviate

  # B) Minimal override without USERS (if still failing)
  if ! curl -fsS -H "X-API-KEY: $KEY" "$BASE/v1/schema" >/dev/null 2>&1; then
    ylw "Still failing with anon off; applying minimal override that removes USERS mapping."

    MIN_OVR="$INFRA_DIR/compose.weaviate.min-auth.yml"
    cat > "$MIN_OVR" <<'YAML'
services:
  weaviate:
    environment:
      AUTHENTICATION_APIKEY_ENABLED: "true"
      AUTHENTICATION_APIKEY_ALLOWED_KEYS: ${WEAVIATE_APIKEY}
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: "false"
      AUTHENTICATION_APIKEY_USERS: ""
YAML
    docker compose --env-file "$ENV_DIR/.env" -f "$INFRA_DIR/compose.core.yml" -f "$MIN_OVR" up -d weaviate
    sleep 3
    printf "  /schema (X-API-KEY) after USERS removal -> "
    curl -s -o /dev/null -w "%{http_code}\n" -H "X-API-KEY: $KEY" "$BASE/v1/schema" || true
  fi
fi

info "Final status"
curl -s -o /dev/null -w "  /ready -> %{http_code}\n" "$BASE/v1/.well-known/ready"
curl -s -o /dev/null -w "  /schema (X-API-KEY) -> %{http_code}\n" -H "X-API-KEY: $KEY" "$BASE/v1/schema"
grn "Done."

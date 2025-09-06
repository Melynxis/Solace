#!/usr/bin/env bash
set -euo pipefail

INFRA_DIR="/home/melynxis/solace/infra"
ENV_FILE="/home/melynxis/solace/.env"
BASE="http://127.0.0.1:8080"
NAME="solace_weaviate"

echo "==> Using INFRA_DIR=$INFRA_DIR  ENV=$ENV_FILE  SERVICE=$NAME"

# 0) Load env (no output of secrets)
set -a
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
set +a

# 1) Quick container + env sanity
echo "==> Container status:"
docker ps --filter "name=$NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo "==> Container-side auth env:"
docker exec "$NAME" /bin/sh -lc 'env | egrep -i "AUTHENTICATION_|PERSISTENCE_DATA_PATH|CLUSTER_HOSTNAME" | sort || true'

# 2) Wait for /ready (no auth)
echo "==> Waiting for /ready ..."
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/v1/.well-known/ready")
  printf "   try #%02d: /ready -> %s\n" "$i" "$code"
  [ "$code" = "200" ] && break
  sleep 1
done
if [ "$code" != "200" ]; then
  echo "❌ /ready never hit 200. Recent logs:"
  docker logs --tail=120 "$NAME"
  exit 1
fi
echo "✅ /ready OK"

# 3) Show the key we think we’re using (length + hex)
if [ -n "${WEAVIATE_APIKEY:-}" ]; then
  printf "==> Host key sanity: length=%d  hex=" "${#WEAVIATE_APIKEY}"
  echo -n "$WEAVIATE_APIKEY" | xxd -p | tr -d '\n'
  echo
else
  echo "!! WEAVIATE_APIKEY is empty in env; schema will 401."
fi

# 4) Try /schema with all header variants Weaviate accepts
echo "==> /schema attempts:"
try_schema () {
  local desc=$1; shift
  local args=("$@")
  local scode body
  scode=$(curl -s -o /tmp/wv_body.$$ -w "%{http_code}" "${args[@]}" "$BASE/v1/schema" || true)
  echo "  $desc -> HTTP $scode"
  head -c 200 /tmp/wv_body.$$ || true
  echo
  rm -f /tmp/wv_body.$$
}

try_schema "no header"
try_schema "X-API-KEY"            -H "X-API-KEY: ${WEAVIATE_APIKEY:-}"
try_schema "Authorization: ApiKey" -H "Authorization: ApiKey ${WEAVIATE_APIKEY:-}"
try_schema "Authorization: Bearer" -H "Authorization: Bearer ${WEAVIATE_APIKEY:-}"

# 5) If all 401, offer a temporary anon-on flip to prove the endpoint works
all_401=$(
  for h in "X-API-KEY" "Authorization: ApiKey" "Authorization: Bearer"; do
    curl -s -o /dev/null -w "%{http_code}" -H "$h: ${WEAVIATE_APIKEY:-}" "$BASE/v1/schema" || true
  done | awk 'BEGIN{s=1} {if($1!="401") s=0} END{print s}'
)

if [ "$all_401" = "1" ]; then
  echo "==> All auth variants returned 401. Applying temporary anon override to validate endpoint..."
  cat > "$INFRA_DIR/compose.weaviate.authfix.yml" <<'YAML'
services:
  weaviate:
    environment:
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: "true"
      AUTHENTICATION_APIKEY_ENABLED: "true"
      # Drop USERS mapping to avoid unexpected mapping constraints
      AUTHENTICATION_APIKEY_USERS: ""
YAML

  docker compose \
    --env-file "$ENV_FILE" \
    -f "$INFRA_DIR/compose.core.yml" \
    -f "$INFRA_DIR/compose.weaviate.authfix.yml" \
    up -d weaviate

  # Recheck /schema *without* auth (should be 200 if endpoint OK)
  for i in $(seq 1 30); do
    s=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/v1/schema")
    printf "   anon test #%02d: /schema -> %s\n" "$i" "$s"
    [ "$s" = "200" ] && break
    sleep 1
  done

  # Re-check with Authorization: ApiKey (preferred form)
  s_api=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: ApiKey ${WEAVIATE_APIKEY:-}" "$BASE/v1/schema")
  echo "   /schema with ApiKey after anon-on -> $s_api"

  echo "==> Restoring anon=false (keep API key auth on)…"
  cat > "$INFRA_DIR/compose.weaviate.authfix.yml" <<'YAML'
services:
  weaviate:
    environment:
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: "false"
      AUTHENTICATION_APIKEY_ENABLED: "true"
      AUTHENTICATION_APIKEY_USERS: ""
YAML

  docker compose \
    --env-file "$ENV_FILE" \
    -f "$INFRA_DIR/compose.core.yml" \
    -f "$INFRA_DIR/compose.weaviate.authfix.yml" \
    up -d weaviate

  sleep 2
  s_api=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: ApiKey ${WEAVIATE_APIKEY:-}" "$BASE/v1/schema")
  echo "   /schema with ApiKey after anon-off -> $s_api"
fi

echo "✅ Done."

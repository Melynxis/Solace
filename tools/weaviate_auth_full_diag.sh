#!/usr/bin/env bash
set -euo pipefail

BASE="http://127.0.0.1:8080"
ENV_FILE="/home/melynxis/solace/.env"
CONTAINER="solace_weaviate"

echo "==> Loading .env from ${ENV_FILE}"
set -a; . "${ENV_FILE}"; set +a

KEY="${WEAVIATE_APIKEY:-}"
if [[ -z "${KEY}" ]]; then
  echo "ERROR: WEAVIATE_APIKEY is empty in ${ENV_FILE}"; exit 1
fi

# Safe temp files (fixes the previous /tmp/wv_body.* race)
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
body="${tmpdir}/body.json"
hdrs="${tmpdir}/resp.txt"

echo "==> Host key sanity"
printf "  length: %s\n" "${#KEY}"
printf "  hex   : %s\n" "$(echo -n "$KEY" | xxd -p -c 256)"

echo "==> Container-side env (auth-related)"
docker exec -it "${CONTAINER}" /bin/sh -lc 'env | egrep -i "^AUTHENTICATION_|^PERSISTENCE_|^CLUSTER_" | sort' || true

echo "==> Quick readiness (should be 200 with or without auth)"
for h in "none" "X-API-KEY" "Authorization: ApiKey" "Authorization: Bearer"; do
  case "$h" in
    none) code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/v1/.well-known/ready");;
    "X-API-KEY") code=$(curl -s -o /dev/null -w "%{http_code}" -H "X-API-KEY: ${KEY}" "$BASE/v1/.well-known/ready");;
    "Authorization: ApiKey") code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: ApiKey ${KEY}" "$BASE/v1/.well-known/ready");;
    "Authorization: Bearer") code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${KEY}" "$BASE/v1/.well-known/ready");;
  esac
  printf "  /ready with %-20s -> %s\n" "$h" "$code"
done

echo "==> /schema attempts (various header forms)"
try_schema() {
  local name="$1"; shift
  local code
  code=$(curl -s -D "$hdrs" -o "$body" -w "%{http_code}" "$@" "$BASE/v1/schema" || true)
  printf "  %-24s -> HTTP %s\n" "$name" "$code"
  printf "    resp-hdrs: "; head -n1 "$hdrs" || true
  printf "    body: "; head -c 240 "$body"; echo
}

try_schema "no header" 
try_schema "X-API-KEY" -H "X-API-KEY: ${KEY}"
try_schema "Auth: ApiKey" -H "Authorization: ApiKey ${KEY}"
try_schema "Auth: Bearer" -H "Authorization: Bearer ${KEY}"

echo "==> GraphQL whoami probe (should reveal the mapped user if auth is accepted)"
cat > "${tmpdir}/whoami.json" <<'JSON'
{ "query": "{ meta { nodes { name, status } } }" }
JSON
gql_code=$(curl -s -D "$hdrs" -o "$body" -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: ${KEY}" \
  -X POST "$BASE/v1/graphql" --data @"${tmpdir}/whoami.json" || true)
printf "  /graphql (X-API-KEY) -> HTTP %s\n" "$gql_code"
printf "    resp-hdrs: "; head -n1 "$hdrs" || true
printf "    body: "; head -c 240 "$body"; echo

echo "==> Server info endpoint (auth & anon variants)"
for h in "none" "X-API-KEY"; do
  case "$h" in
    none) code=$(curl -s -o "$body" -w "%{http_code}" "$BASE/v1/.well-known/diagnostics" || true);;
    "X-API-KEY") code=$(curl -s -o "$body" -w "%{http_code}" -H "X-API-KEY: ${KEY}" "$BASE/v1/.well-known/diagnostics" || true);;
  esac
  printf "  /diagnostics (%s) -> %s\n" "$h" "$code"
  head -c 200 "$body" | tr -d '\n'; echo
done

echo "==> Last 60 lines mentioning auth in logs"
docker logs --tail=200 "${CONTAINER}" 2>&1 | egrep -i "auth|ready|schema|raft|cluster" | tail -n 60 || true

echo "==> OPTIONAL AUTO-FIX (only runs if explicit envs look correct but /schema keeps 401)"
# If keys match and anon=false, try a minimal override that some versions require:
#  - explicitly set AUTHENTICATION_APIKEY_USERS to empty (disable mapping)
#  - keep apikeys enabled and allowed_keys
cat > "${tmpdir}/compose.weaviate.min.yml" <<YAML
services:
  weaviate:
    environment:
      AUTHENTICATION_APIKEY_ENABLED: "true"
      AUTHENTICATION_APIKEY_ALLOWED_KEYS: "${KEY}"
      AUTHENTICATION_APIKEY_USERS: ""
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: "false"
YAML

if curl -s -H "X-API-KEY: ${KEY}" "$BASE/v1/schema" -o /dev/null -w "%{http_code}" | grep -q '^401$'; then
  echo "   -> Applying minimal override (drop USERS mapping) and restarting only Weaviate…"
  docker compose -f /home/melynxis/solace/infra/compose.core.yml -f "${tmpdir}/compose.weaviate.min.yml" up -d weaviate
  sleep 3
  code=$(curl -s -o /dev/null -w "%{http_code}" -H "X-API-KEY: ${KEY}" "$BASE/v1/schema" || true)
  echo "   -> Post-restart /schema with X-API-KEY -> ${code}"
fi

echo "✅ Done."

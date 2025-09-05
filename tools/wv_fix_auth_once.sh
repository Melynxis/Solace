#!/usr/bin/env bash
set -euo pipefail

INFRA_DIR="/home/melynxis/solace/infra"
ENV_FILE="/home/melynxis/solace/.env"
OVERRIDE_YML="${INFRA_DIR}/compose.weaviate.override.yml"
SERVICE="weaviate"
BASE="http://127.0.0.1:8080"

echo "==> Loading env from ${ENV_FILE}"
set -a; . "${ENV_FILE}"; set +a

if [[ -z "${WEAVIATE_APIKEY:-}" ]]; then
  echo "ERROR: WEAVIATE_APIKEY is not set in ${ENV_FILE}" >&2
  exit 1
fi

echo "==> Writing a minimal single-node auth override to ${OVERRIDE_YML}"
cat > "${OVERRIDE_YML}" <<'YAML'
services:
  weaviate:
    environment:
      # Single-node raft
      CLUSTER_HOSTNAME: "node1"

      # Turn ON API-key auth, turn OFF anonymous access
      AUTHENTICATION_APIKEY_ENABLED: "true"
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: "false"

      # Allowed keys must EXACTLY match the host WEAVIATE_APIKEY.
      # We let compose inject it from .env at runtime.
      AUTHENTICATION_APIKEY_ALLOWED_KEYS: "${WEAVIATE_APIKEY}"

      # Do NOT set USERS mapping (it can cause unexpected 401s)
      AUTHENTICATION_APIKEY_USERS: ""

      # Use local data path as before
      PERSISTENCE_DATA_PATH: "/var/lib/weaviate"
YAML

echo "==> Restarting Weaviate with core+override and explicit env-file"
cd "${INFRA_DIR}"
docker compose --env-file "${ENV_FILE}" -f compose.core.yml -f compose.weaviate.override.yml up -d ${SERVICE}

echo "==> Waiting for /ready (up to 60s)…"
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE}/v1/.well-known/ready" || true)
  [[ "${code}" == "200" ]] && { echo "   ready=200"; break; }
  sleep 1
  [[ "${i}" == "60" ]] && { echo "   ❌ never reached /ready; recent logs:"; docker logs --tail=120 "solace_weaviate"; exit 1; }
done

echo "==> Verifying container-side env (auth)"
docker exec solace_weaviate /bin/sh -lc 'env | egrep -i "AUTHENTICATION_|CLUSTER_HOSTNAME|PERSISTENCE_DATA_PATH" | sort'

echo "==> /schema tests"
echo "  - X-API-KEY header"
curl -s -w "\nhttp=%{http_code}\n" -H "X-API-KEY: ${WEAVIATE_APIKEY}" "${BASE}/v1/schema" | sed -e 's/{"code":401.*/401 Unauthorized (body omitted)/'
echo "  - Authorization: Bearer (may 401, that’s OK on this build)"
curl -s -w "\nhttp=%{http_code}\n" -H "Authorization: Bearer ${WEAVIATE_APIKEY}" "${BASE}/v1/schema" | sed -e 's/{"code":401.*/401 Unauthorized (body omitted)/'

echo "==> Result hints"
echo "  • EXPECTED: X-API-KEY -> http=200; Bearer -> http=401 on this image."
echo "  • If X-API-KEY is still 401: key mismatch or override not applied."
echo "    - Confirm: docker exec solace_weaviate printenv AUTHENTICATION_APIKEY_ALLOWED_KEYS"
echo "    - It must exactly equal your .env WEAVIATE_APIKEY."

#!/usr/bin/env bash
# fix_weaviate_single_node_hard_reset.sh
# Purpose: clear any stale Raft/cluster state and (re)start Weaviate as a clean single node.
# Assumes your compose and .env live under /home/melynxis/solace/infra and /home/melynxis/solace/.env

set -euo pipefail

PROJECT_DIR="/home/melynxis/solace"
COMPOSE_CORE="${PROJECT_DIR}/infra/compose.core.yml"
OVERRIDE="${PROJECT_DIR}/infra/compose.weaviate.override.yml"
BACKUP_ROOT="/home/melynxis/run/backups"
WEAV_DIR="/var/lib/weaviate"
TS="$(date +%s)"

echo "==> Making sure .env is there and readable"
if [[ -f "${PROJECT_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${PROJECT_DIR}/.env"
  set +a
else
  echo "WARN: ${PROJECT_DIR}/.env not found; compose will still run but auth/apikey settings may be defaults."
fi

echo "==> Stopping Weaviate only (leaving MySQL/Redis alone)"
docker compose -f "${COMPOSE_CORE}" rm -s -f weaviate >/dev/null 2>&1 || true

echo "==> Backing up and wiping ${WEAV_DIR} (stale Raft state often causes join loops)"
sudo mkdir -p "${BACKUP_ROOT}/weaviate.${TS}"
if [[ -d "${WEAV_DIR}" ]]; then
  sudo rsync -a --delete "${WEAV_DIR}/" "${BACKUP_ROOT}/weaviate.${TS}/" || true
  sudo find "${WEAV_DIR}" -mindepth 1 -maxdepth 1 -print -exec sudo rm -rf {} \;
else
  echo "INFO: ${WEAV_DIR} did not exist; creating"
  sudo mkdir -p "${WEAV_DIR}"
  sudo chown -R "$(id -un)":"$(id -gn)" "${WEAV_DIR}" || true
fi

echo "==> Writing a minimal single-node override to ${OVERRIDE}"
cat > "${OVERRIDE}" <<'YML'
services:
  weaviate:
    environment:
      # Single-node identity
      CLUSTER_HOSTNAME: node1

      # Common safe defaults (keep yours from compose/.env as well)
      PERSISTENCE_DATA_PATH: /var/lib/weaviate
      DEFAULT_VECTORIZER_MODULE: none
      QUERY_DEFAULTS_LIMIT: "25"

      # Auth — respect .env if present
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: "false"
      # If WEAVIATE_APIKEY is exported from .env, compose passes it through.
      # Otherwise you can hard-set AUTHENTICATION_APIKEYS here like: ["mykey"]
      # AUTHENTICATION_APIKEYS: '["'"${WEAVIATE_APIKEY:-}"'"]'
YML

echo "==> Starting Weaviate with override"
docker compose -f "${COMPOSE_CORE}" -f "${OVERRIDE}" up -d weaviate

echo "==> Waiting for Weaviate readiness (HTTP 200) ..."
ATTEMPTS=60
SLEEP=2
READY=0
for i in $(seq 1 $ATTEMPTS); do
  if curl -fsS http://127.0.0.1:8080/v1/.well-known/ready >/dev/null; then
    READY=1
    break
  fi
  sleep $SLEEP
done

if [[ $READY -eq 1 ]]; then
  echo "✅ Weaviate is ready."
  echo "   Tip: curl -s http://127.0.0.1:8080/v1/.well-known/ready | jq ."
else
  echo "❌ Still not ready. Showing last 80 log lines:"
  docker logs --tail=80 solace_weaviate || true
  exit 1
fi

echo "==> Done. Backup of previous data (if any): ${BACKUP_ROOT}/weaviate.${TS}"

#!/usr/bin/env bash
set -euo pipefail

INFRA_DIR="/home/melynxis/solace/infra"
ENV_FILE="/home/melynxis/solace/.env"
SERVICE="weaviate"
CONTAINER="solace_weaviate"
VOL_NAME="solace-core_weaviate_data"
DATA_DIR="/var/lib/weaviate"

echo "==> Using INFRA_DIR=$INFRA_DIR  ENV=$ENV_FILE  VOL=$VOL_NAME  DATA_DIR=$DATA_DIR"

# 0) Load env (for WEAVIATE_APIKEY). This won't export to compose unless we pass --env-file later.
if [ -f "$ENV_FILE" ]; then
  set -a; . "$ENV_FILE"; set +a
else
  echo "WARN: $ENV_FILE not found; continuing."
fi

# 1) Stop only Weaviate
echo "==> Stopping Weaviate container"
docker compose -f "$INFRA_DIR/compose.core.yml" stop $SERVICE || true
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

# 2) Remove the docker volume if present (prevents mounted stale raft state)
echo "==> Removing docker volume $VOL_NAME (if present)"
docker volume rm "$VOL_NAME" >/dev/null 2>&1 || true

# 3) Make sure the host data dir is free of stale state and not mounted
echo "==> Releasing any mounts & wiping stale raft/schema on host"
if mountpoint -q "$DATA_DIR"; then
  echo "   $DATA_DIR is a mountpoint; lazy umount…"
  sudo umount -l "$DATA_DIR" || true
fi
sudo mkdir -p "$DATA_DIR"
sudo rm -rf "$DATA_DIR/raft" "$DATA_DIR/schema.db" "$DATA_DIR/classifications.db" \
            "$DATA_DIR/modules.db" "$DATA_DIR/migration"* || true

# 4) Write a minimal single-node override that ALSO pins auth to API key
#    (This file is merged with compose.core.yml)
OVR="$INFRA_DIR/compose.weaviate.override.yml"
echo "==> Writing $OVR"
cat <<'YAML' | tee "$OVR" >/dev/null
services:
  weaviate:
    environment:
      # --- single-node cluster settings ---
      CLUSTER_HOSTNAME: "node1"
      # No peer list -> bootstrap self

      # --- auth (API key) ---
      AUTHENTICATION_APIKEY_ENABLED: "true"
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: "false"
      AUTHENTICATION_APIKEY_ALLOWED_KEYS: "${WEAVIATE_APIKEY}"
      AUTHENTICATION_APIKEY_USERS: "solace"

      # --- other sane defaults ---
      DEFAULT_VECTORIZER_MODULE: "none"
    volumes:
      - solace-core_weaviate_data:/var/lib/weaviate
YAML

# 5) Bring up only Weaviate with BOTH files and the env-file so $WEAVIATE_APIKEY flows in
echo "==> Starting Weaviate with core+override and explicit env-file"
docker compose \
  --env-file "$ENV_FILE" \
  -f "$INFRA_DIR/compose.core.yml" \
  -f "$OVR" \
  up -d $SERVICE

echo "==> Tail last 40 logs (watch for bootstrap -> leader)"
sleep 2
docker logs --tail=40 "$CONTAINER" || true

# 6) Readiness (inside container and host). Inside avoids host networking quirks.
echo "==> In-container readiness probe"
docker exec "$CONTAINER" sh -lc '
  for i in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/v1/.well-known/ready)
    echo "  in-container /ready -> $code"
    [ "$code" = "200" ] && exit 0
    sleep 1
  done
  exit 1
'

echo "==> Host readiness probe"
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/v1/.well-known/ready)
  echo "  host /ready -> $code"
  [ "$code" = "200" ] && break
  sleep 1
done

# 7) Schema auth check — NOTE: 1.32.x accepts X-API-KEY, Bearer may 403/401 without OIDC
BASE="http://127.0.0.1:8080"
echo "==> /schema with X-API-KEY (expected 200)"
curl -fsS -H "X-API-KEY: ${WEAVIATE_APIKEY:-}" "$BASE/v1/schema" | jq . || true

echo "==> /schema with Authorization: Bearer (may 401/403 if OIDC not configured)"
code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${WEAVIATE_APIKEY:-}" "$BASE/v1/schema")
echo "  bearer http=$code"

echo "✅ Done. If /ready is 200 and schema(X-API-KEY) returns JSON, you’re good."

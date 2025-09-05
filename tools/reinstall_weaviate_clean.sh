#!/usr/bin/env bash
set -euo pipefail

INFRA_DIR="/home/melynxis/solace/infra"
ENV_FILE="/home/melynxis/solace/.env"
DATA_DIR="/var/lib/weaviate"
VOL_NAME="solace-core_weaviate_data"
BACKUP_DIR="/home/melynxis/run/backups/weaviate.$(date +%s)"

echo "==> Using INFRA_DIR=$INFRA_DIR  DATA_DIR=$DATA_DIR  VOL_NAME=$VOL_NAME"

# 0) Load env if present (don’t fail if missing)
if [ -f "$ENV_FILE" ]; then
  echo "==> Loading env from $ENV_FILE"
  set -a; . "$ENV_FILE"; set +a
fi

cd "$INFRA_DIR"

# 1) Stop/remove Weaviate container only
echo "==> Stopping Weaviate container (leaving MySQL/Redis up)"
docker compose -f compose.core.yml stop weaviate || true
docker rm -f solace_weaviate >/dev/null 2>&1 || true

# 2) If a docker volume still exists, remove it (it may keep the host path busy)
if docker volume inspect "$VOL_NAME" >/dev/null 2>&1; then
  echo "==> Removing docker volume $VOL_NAME"
  docker volume rm -f "$VOL_NAME" || true
fi

# 3) Kill any processes with open handles on DATA_DIR (host-side)
echo "==> Releasing file handles on $DATA_DIR (if any)"
sudo fuser -km "$DATA_DIR" >/dev/null 2>&1 || true

# 4) If $DATA_DIR is a mount point, unmount it (lazy umount to break bind)
if mountpoint -q "$DATA_DIR"; then
  echo "==> $DATA_DIR is a mountpoint; performing lazy umount"
  sudo umount -l "$DATA_DIR" || true
fi

# 5) Backup (if anything to back up) and wipe the directory
if [ -d "$DATA_DIR" ] && [ -n "$(ls -A "$DATA_DIR" 2>/dev/null || true)" ]; then
  echo "==> Backing up $DATA_DIR -> $BACKUP_DIR"
  sudo mkdir -p "$BACKUP_DIR"
  sudo rsync -aHAX --delete "$DATA_DIR"/ "$BACKUP_DIR"/
fi

echo "==> Recreating clean $DATA_DIR"
sudo mkdir -p "$DATA_DIR"
# Weaviate runs as root in the official image; root:root is fine
sudo chown root:root "$DATA_DIR"
sudo chmod 755 "$DATA_DIR"
sudo rm -rf "$DATA_DIR"/*

# 6) Recreate the docker volume as a bind to DATA_DIR (so Compose can use it)
echo "==> Creating bind volume $VOL_NAME -> $DATA_DIR"
docker volume create \
  --name "$VOL_NAME" \
  --opt type=none \
  --opt o=bind \
  --opt device="$DATA_DIR" >/dev/null

# 7) Bring ONLY Weaviate up using core + override (so single-node/raft init applies)
echo "==> Starting Weaviate with override (core + compose.weaviate.override.yml)"
docker compose -f compose.core.yml -f compose.weaviate.override.yml up -d weaviate

# 8) Readiness loop; try both with and without key (depending on your auth config)
BASE="http://127.0.0.1:8080"
KEY_HEADER=()
if [ -n "${WEAVIATE_APIKEY:-}" ]; then
  KEY_HEADER=(-H "X-API-KEY: ${WEAVIATE_APIKEY}")
fi

echo "==> Waiting for /ready (up to 60s)..."
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/v1/.well-known/ready")
  [ "$code" = "200" ] && break
  sleep 1
done
curl -fsS "$BASE/v1/.well-known/ready" >/dev/null
echo "   /ready OK"

# 9) /schema check (auth typically required when anonymous is disabled)
echo "==> Checking /schema with auth header"
SCHEMA_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${KEY_HEADER[@]}" "$BASE/v1/schema")
if [ "$SCHEMA_CODE" != "200" ]; then
  echo "!! /schema still not 200 (got $SCHEMA_CODE). Dumping a short error body:"
  curl -s "${KEY_HEADER[@]}" "$BASE/v1/schema" | head -c 400 || true
  echo
  echo "Hint:"
  echo "  - Ensure WEAVIATE_APIKEY is set in $ENV_FILE without quotes or spaces."
  echo "  - Container env should show AUTHENTICATION_APIKEY_ENABLED=true,"
  echo "    AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=false,"
  echo "    AUTHENTICATION_APIKEY_ALLOWED_KEYS=<same key>."
  exit 1
fi

echo "✅ Weaviate reinstalled clean and responding to authorized /schema."

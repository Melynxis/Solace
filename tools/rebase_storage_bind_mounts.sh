#!/usr/bin/env bash
set -euo pipefail

BASE="/home/melynxis/solace"
CORE="$BASE/infra/compose.core.yml"
OVR="$BASE/infra/compose.core.override.yml"
BKDIR="/home/melynxis/run/backups/volumes.$(date +%s)"

MYSQL_VOL="solace-core_mysql_data"
WEAV_VOL="solace-core_weaviate_data"

# Target host paths (already mounted per your audit)
MYSQL_HOST_DIR="/var/lib/mysql"
WEAV_HOST_DIR="/var/lib/weaviate"
REDIS_HOST_DIR="/home/melynxis/run/redis"

echo "==> Preparing dirs"
sudo mkdir -p "$MYSQL_HOST_DIR" "$WEAV_HOST_DIR" "$REDIS_HOST_DIR" "$BKDIR"
sudo chown -R 999:999 "$MYSQL_HOST_DIR" || true     # mysql uid often 999
sudo chown -R 1001:1001 "$WEAV_HOST_DIR" || true    # weaviate runs as non-root in some images; harmless if not
sudo chown -R 1001:1001 "$REDIS_HOST_DIR" || true   # redis may run as non-root; harmless if not

echo "==> Stopping core services"
docker compose -f "$CORE" down

backup_volume () {
  local v="$1"
  if docker volume inspect "$v" >/dev/null 2>&1; then
    echo "   -> Backing up volume $v to $BKDIR/$v.tgz"
    docker run --rm -v "$v":/from -v "$BKDIR":/to alpine sh -c 'cd /from && tar -czf /to/'"$v.tgz"' . || true'
    echo "   -> Removing volume $v"
    docker volume rm "$v" || true
  else
    echo "   -> Volume $v not present (skipping backup/removal)"
  fi
}

echo "==> Backing up & removing named volumes (if present)"
backup_volume "$MYSQL_VOL"
backup_volume "$WEAV_VOL"

echo "==> Re-creating named volumes as bind-mounts"
docker volume create --driver local \
  -o type=none -o o=bind -o device="$MYSQL_HOST_DIR" "$MYSQL_VOL" >/dev/null

docker volume create --driver local \
  -o type=none -o o=bind -o device="$WEAV_HOST_DIR" "$WEAV_VOL" >/dev/null

echo "==> Writing Redis override compose (bind /data -> $REDIS_HOST_DIR)"
cat > "$OVR" <<YAML
services:
  redis:
    volumes:
      - $REDIS_HOST_DIR:/data
YAML

echo "==> Bringing stack back up with override"
docker compose -f "$CORE" -f "$OVR" up -d

echo "==> Verifying mounts"
for c in solace_mysql solace_weaviate solace_redis; do
  echo "[$c] mounts:"
  docker inspect "$c" --format '{{json .Mounts}}' | jq -r '.[] | "  - " + (.Source + " -> " + .Destination)'
done

echo "==> Quick readiness checks"
echo "MySQL ping..."
ROOTPW="$(. "$BASE/.env"; echo "${MYSQL_ROOT_PASSWORD:-}")"
if [ -n "$ROOTPW" ]; then
  docker exec -i solace_mysql mysql -uroot -p"$ROOTPW" -e "SELECT 1;" >/dev/null && echo "  ok" || echo "  FAIL"
else
  echo "  (skip: no MYSQL_ROOT_PASSWORD in .env)"
fi

echo "Weaviate readiness..."
curl -fsS http://127.0.0.1:8080/v1/.well-known/ready || echo "  not ready"

echo "Redis INFO persistence..."
REDISPW="$(. "$BASE/.env"; echo "${REDIS_PASSWORD:-}")"
if [ -n "$REDISPW" ]; then
  docker exec -i solace_redis redis-cli -a "$REDISPW" INFO persistence | grep -E 'loading|aof_enabled|rdb_' | sed 's/^/  /'
else
  echo "  (skip: no REDIS_PASSWORD in .env)"
fi

echo "✅ Storage rebased to designated disks."

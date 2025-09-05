#!/usr/bin/env bash
set -euo pipefail

BASE="/home/melynxis/solace"
CORE="infra/compose.core.yml"
OVR="infra/compose.core.override.yml"
ENV="$BASE/.env"

# sanity
[[ -f "$ENV" ]] || { echo "Missing $ENV"; exit 1; }

echo "==> Stopping core using the correct project directory (so .env is picked up)"
docker compose \
  --project-directory "$BASE" \
  --env-file "$ENV" \
  -f "$BASE/$CORE" -f "$BASE/$OVR" down || true

echo "==> Backing up and re-initializing MySQL datadir (so it picks up MYSQL_ROOT_PASSWORD)"
BK="/home/melynxis/run/backups/mysql.$(date +%s)"
sudo mkdir -p "$BK"
if [ -d /var/lib/mysql ] && [ "$(ls -A /var/lib/mysql || true)" ]; then
  echo "   backing up /var/lib/mysql -> $BK"
  sudo rsync -aHAX --numeric-ids /var/lib/mysql/ "$BK"/
  echo "   wiping /var/lib/mysql for fresh init"
  sudo find /var/lib/mysql -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi
sudo chown -R 999:999 /var/lib/mysql || true

echo "==> Starting core WITH .env explicitly"
docker compose \
  --project-directory "$BASE" \
  --env-file "$ENV" \
  -f "$BASE/$CORE" -f "$BASE/$OVR" up -d

echo "==> Waiting for MySQL to listen (up to 40s)..."
for i in {1..20}; do
  if docker exec solace_mysql sh -c "exec 3<>/dev/tcp/127.0.0.1/3306" 2>/dev/null; then
    echo "   MySQL port open"
    break
  fi
  sleep 2
done

ROOTPW="$(. "$ENV"; echo "${MYSQL_ROOT_PASSWORD:-}")"
REDISPW="$(. "$ENV"; echo "${REDIS_PASSWORD:-}")"

echo "==> MySQL ping (TCP)"
if [ -n "$ROOTPW" ]; then
  docker exec -i solace_mysql mysql -h 127.0.0.1 -uroot -p"$ROOTPW" -e "SELECT 1;" && echo "   ok" || echo "   FAIL"
else
  echo "   (no MYSQL_ROOT_PASSWORD in .env?)"
fi

echo "==> Redis auth/ping"
if [ -n "$REDISPW" ]; then
  docker exec -i solace_redis redis-cli -a "$REDISPW" PING || true
else
  echo "   (no REDIS_PASSWORD in .env?)"
fi

echo "==> Weaviate readiness"
curl -fsS http://127.0.0.1:8080/v1/.well-known/ready || { echo "   not ready; tailing logs:"; docker logs --tail=60 solace_weaviate || true; }

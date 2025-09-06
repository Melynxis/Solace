#!/usr/bin/env bash
set -euo pipefail

BASE="/home/melynxis/solace"
CORE="${BASE}/infra/compose.core.yml"
OVR="${BASE}/infra/compose.core.override.yml"

# 1) Write an override that uses explicit bind mounts (no ambiguity) and enforces Redis auth
cat > "$OVR" <<'YAML'
services:
  mysql:
    volumes:
      - /var/lib/mysql:/var/lib/mysql

  weaviate:
    volumes:
      - /var/lib/weaviate:/var/lib/weaviate

  redis:
    # enforce password; official image needs --requirepass (env alone is ignored)
    command: ["redis-server", "--appendonly", "no", "--save", "", "--requirepass", "${REDIS_PASSWORD}"]
    volumes:
      - /home/melynxis/run/redis:/data
YAML

# 2) Bring the stack up with the override
echo "==> (re)starting core with explicit bind mounts + redis auth"
docker compose -f "$CORE" -f "$OVR" up -d

# 3) Show mounts as seen by containers
echo "==> mounts now:"
for c in solace_mysql solace_weaviate solace_redis; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$c"; then
    echo "[$c]"
    docker inspect "$c" --format '{{json .Mounts}}' | jq -r '.[] | "  - " + (.Source + " -> " + .Destination)'
  fi
done

# 4) Quick health checks

# MySQL (force TCP so we don't hit the socket)
echo "==> mysql ping:"
ROOTPW="$(. "$BASE/.env"; echo "${MYSQL_ROOT_PASSWORD:-}")"
if [[ -n "$ROOTPW" ]]; then
  docker exec -i solace_mysql mysql -h 127.0.0.1 -uroot -p"$ROOTPW" -e "SELECT 1;" >/dev/null && echo "  ok" || echo "  FAIL"
else
  echo "  (skip: MYSQL_ROOT_PASSWORD not set in $BASE/.env)"
fi

# Redis (auth required now)
echo "==> redis auth/ping:"
REDISPW="$(. "$BASE/.env"; echo "${REDIS_PASSWORD:-}")"
if [[ -n "$REDISPW" ]]; then
  docker exec -i solace_redis redis-cli -a "$REDISPW" PING || true
else
  echo "  (skip: REDIS_PASSWORD not set in $BASE/.env)"
fi

# Weaviate (readiness + last log lines to diagnose if not ready)
echo "==> weaviate readiness:"
if curl -fsS http://127.0.0.1:8080/v1/.well-known/ready >/dev/null; then
  echo "  ready"
else
  echo "  not ready, last 60 log lines:"
  docker logs --tail=60 solace_weaviate || true
fi

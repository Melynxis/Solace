# /home/melynxis/solace/tools/audit_paths.sh
#!/usr/bin/env bash
set -euo pipefail

BASE="/home/melynxis/solace"
ENV_FILE="$BASE/.env"

echo "=== Solace PATHS AUDIT ==="
echo "Base: $BASE"
echo

echo "[.env] (top relevant keys)"
if [[ -f "$ENV_FILE" ]]; then
  grep -E '^(MYSQL_HOST|MYSQL_PORT|MYSQL_DB|MYSQL_USER|MYSQL_PASSWORD|REDIS_PASSWORD|WEAVIATE_.*|REGISTRY_PORT)=' "$ENV_FILE" || true
else
  echo "  (no .env found at $ENV_FILE)"
fi
echo

# Helper to print mounts for a container if it exists
print_mounts () {
  local name="$1"
  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    echo "[$name] Mounts:"
    docker inspect "$name" --format '{{json .Mounts}}' | jq -r '.[] | "  - " + (.Type + " " + .Source + " -> " + .Destination)'
  else
    echo "[$name] not found"
  fi
  echo
}

print_ports () {
  local name="$1"
  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    echo "[$name] Ports:"
    docker inspect "$name" --format '{{json .NetworkSettings.Ports}}' | jq -r 'to_entries[]? | "  - " + .key + " -> " + (.value[0].HostIp + ":" + .value[0].HostPort)'
  else
    echo "[$name] not found"
  fi
  echo
}

print_networks () {
  local name="$1"
  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    echo "[$name] Networks:"
    docker inspect "$name" --format '{{json .NetworkSettings.Networks}}' | jq -r 'to_entries[]? | "  - " + .key + " (IP: " + .value.IPAddress + ")"'
  else
    echo "[$name] not found"
  fi
  echo
}

echo "=== Docker containers (mounts / ports / networks) ==="
for c in solace_mysql solace_redis solace_weaviate solace_node_exporter solace_mysqld_exporter solace_redis_exporter solace_blackbox_exporter; do
  print_mounts "$c"
  print_ports "$c"
  print_networks "$c"
done

echo "=== Compose files present ==="
ls -l "$BASE/infra" | sed 's/^/  /'
echo

echo "=== Likely data directories (existence + perms) ==="
for d in \
  "$BASE/data" \
  "$BASE/data/mysql" \
  "$BASE/data/redis" \
  "$BASE/data/weaviate" \
  "$BASE/services" \
  "$BASE/services/registry" \
  ; do
  printf "  %-40s : " "$d"
  if [[ -e "$d" ]]; then
    stat -c '%A %U:%G %s bytes' "$d"
  else
    echo "MISSING"
  fi
done
echo

echo "=== MySQL server variables (datadir) ==="
if docker ps --format '{{.Names}}' | grep -qx solace_mysql; then
  ROOTPW="$(. "$ENV_FILE"; echo "${MYSQL_ROOT_PASSWORD:-}")"
  if [[ -n "${ROOTPW}" ]]; then
    docker exec -i solace_mysql mysql -uroot -p"$ROOTPW" -N -e "SHOW VARIABLES LIKE 'datadir';" || true
  else
    echo "  (MYSQL_ROOT_PASSWORD not in .env; skipping)"
  fi
else
  echo "  solace_mysql container not found"
fi

echo
echo "=== Weaviate config probe (env + readiness) ==="
if docker ps --format '{{.Names}}' | grep -qx solace_weaviate; then
  echo "  Env (subset):"
  docker inspect solace_weaviate --format '{{json .Config.Env}}' | jq -r '.[] | select(test("WEAVIATE|AUTH|DEFAULT")) | "    - " + .'
  echo "  Ready?:"
  curl -fsS http://127.0.0.1:8080/v1/.well-known/ready || echo "  (not ready)"
else
  echo "  solace_weaviate container not found"
fi

echo
echo "=== Redis INFO (databases / persistence) ==="
if docker ps --format '{{.Names}}' | grep -qx solace_redis; then
  REDISPW="$(. "$ENV_FILE"; echo "${REDIS_PASSWORD:-}")"
  if [[ -n "${REDISPW}" ]]; then
    docker exec -i solace_redis redis-cli -a "$REDISPW" INFO persistence | sed 's/^/  /' || true
  else
    echo "  (REDIS_PASSWORD not in .env; skipping)"
  fi
else
  echo "  solace_redis container not found"
fi

echo
echo "=== DONE ==="

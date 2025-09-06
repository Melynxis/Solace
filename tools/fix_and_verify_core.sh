#!/usr/bin/env bash
# /home/melynxis/solace/tools/fix_and_verify_core.sh
# Fixes:
#  - Create/repair MySQL app user & GRANTs based on .env
#  - Ensure redis-cli is installed and PINGs with password
#  - Wait for Weaviate readiness
# Then verifies all 3 services.
set -euo pipefail

SOLACE_DIR="/home/melynxis/solace"
cd "$SOLACE_DIR"

if [[ ! -f .env ]]; then
  echo "ERROR: $SOLACE_DIR/.env not found."; exit 1
fi

# Load .env (only keys we use)
export $(grep -E '^(MYSQL_USER|MYSQL_PASSWORD|MYSQL_ROOT_PASSWORD|MYSQL_DB|REDIS_PASSWORD|WEAVIATE_APIKEY)=' .env | xargs -d '\n' -I {} bash -c 'k="${0%%=*}"; v="${0#*=}"; printf "%s=%q\n" "$k" "$v"' {} | xargs)

MYSQL_USER="${MYSQL_USER:-solace_app}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
MYSQL_DB="${MYSQL_DB:-solace}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
WEAVIATE_APIKEY="${WEAVIATE_APIKEY:-}"

echo "==> Using .env:"
echo "    MYSQL_DB=${MYSQL_DB}  MYSQL_USER=${MYSQL_USER}"
echo "    (passwords hidden)"

# Helper: run mysql inside the container as root over TCP
mysql_root_exec() {
  docker exec -i solace_mysql \
    mysql --protocol=TCP -h 127.0.0.1 -P 3306 -uroot -p"${MYSQL_ROOT_PASSWORD}" "$@"
}

# --- MySQL: ensure root password present ---
echo "==> MySQL: sanity-check root connectivity..."
if [[ -z "${MYSQL_ROOT_PASSWORD}" ]]; then
  echo "ERROR: MYSQL_ROOT_PASSWORD is empty in .env. Cannot repair grants."; exit 1
fi

set +e
docker exec solace_mysql sh -c 'true' >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "ERROR: container 'solace_mysql' not running."; exit 1
fi
set -e

# Wait for port inside container
echo "    Waiting for mysqld to listen in container..."
for i in {1..40}; do
  if docker exec solace_mysql sh -c '</dev/tcp/127.0.0.1/3306' >/dev/null 2>&1; then
    break
  fi
  sleep 1
  [[ $i -eq 40 ]] && { echo "ERROR: mysqld not listening."; exit 1; }
done

echo "    Root ping..."
set +e
mysql_root_exec -e "SELECT 1;" >/dev/null 2>&1
MYSQL_ROOT_OK=$?
set -e
if [[ $MYSQL_ROOT_OK -ne 0 ]]; then
  echo "ERROR: root login failed with MYSQL_ROOT_PASSWORD from .env"; exit 1
fi
echo "    Root OK."

# --- MySQL: create/repair app user & grants ---
# Strategy: prefer least privilege but ensure working now.
#  - Create/alter user on '%' so host matches across docker/host/subnets
#  - Grant all on ${MYSQL_DB}.*
# If you want to tighten later, you can replace '%' with '192.168.1.%' and '127.0.0.1'
echo "==> MySQL: ensuring user '${MYSQL_USER}' exists and has GRANTs on '${MYSQL_DB}'..."
mysql_root_exec <<SQL
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
ALTER USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DB}\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
SQL
echo "    User & grants applied."

# Verify app login
echo "    Verifying app login..."
set +e
docker exec -i solace_mysql \
  mysql --protocol=TCP -h 127.0.0.1 -P 3306 -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" \
  -e "SELECT DATABASE();" "${MYSQL_DB}" >/dev/null 2>&1
APP_OK=$?
set -e
if [[ $APP_OK -ne 0 ]]; then
  echo "ERROR: app login still failing. Check passwords in .env and container logs."; exit 1
fi
echo "    App login OK."

# --- Redis: ensure redis-cli & PING with password ---
echo "==> Redis: ensuring redis-cli is installed and PING works..."
if ! command -v redis-cli >/dev/null 2>&1; then
  echo "    Installing redis-tools (requires sudo)..."
  sudo apt-get update -y && sudo apt-get install -y redis-tools
fi

# If your Redis runs in the container and is published on 6379 host, ping localhost
set +e
if [[ -n "${REDIS_PASSWORD}" ]]; then
  redis-cli -h 127.0.0.1 -p 6379 -a "${REDIS_PASSWORD}" PING 2>/dev/null | grep -q PONG
else
  redis-cli -h 127.0.0.1 -p 6379 PING 2>/dev/null | grep -q PONG
fi
REDIS_OK=$?
set -e

if [[ $REDIS_OK -ne 0 ]]; then
  echo "ERROR: Redis PING failed. If you recently added a password, ensure the container uses it."
  echo "       Check: docker logs --tail=200 solace_redis"
  exit 1
fi
echo "    Redis PONG OK."

# --- Weaviate: readiness ---
echo "==> Weaviate: waiting for readiness (HTTP 200) ..."
# (Auth is enforced for API calls, but readiness endpoints should be public 200/204.)
READY=0
for i in {1..60}; do
  if curl -fsS http://127.0.0.1:8080/v1/.well-known/ready >/dev/null 2>&1; then
    READY=1; break
  fi
  sleep 1
done
if [[ $READY -ne 1 ]]; then
  echo "ERROR: Weaviate not ready; recent logs:"
  docker logs --tail=200 solace_weaviate || true
  exit 1
fi
echo "    Weaviate ready."

# --- Final verification summary ---
echo
echo "✅ All checks passed."
echo "   - MySQL app user '${MYSQL_USER}' can connect to DB '${MYSQL_DB}'"
echo "   - Redis responded to PING"
echo "   - Weaviate readiness OK"

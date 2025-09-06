#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="/home/melynxis/solace"
COMPOSE_CORE="$CORE_DIR/infra/compose.core.yml"

cd "$CORE_DIR"

if [[ ! -f ".env" ]]; then
  echo "❌ .env not found at $CORE_DIR"
  exit 1
fi

# Load .env safely into this shell
set -a
source <(grep -v '^[[:space:]]*#' .env | sed 's/\r$//')
set +a

echo "==> Using .env (passwords hidden)"
echo "    MYSQL_DB=${MYSQL_DB:-solace}  MYSQL_USER=${MYSQL_USER:-solace_app}"

echo "==> Ensuring core containers are up"
if ! docker ps --format '{{.Names}}' | grep -q '^solace_mysql$'; then
  docker compose -f "$COMPOSE_CORE" up -d
fi

# Quick status
echo "==> Current container status:"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E '^NAMES|solace_(mysql|redis|weaviate)'

# --- Wait for MySQL TCP ---
echo "==> Waiting for MySQL on 127.0.0.1:3306 ..."
for i in {1..40}; do
  if (echo > /dev/tcp/127.0.0.1/3306) >/dev/null 2>&1; then
    break
  fi
  sleep 1
  [[ $i -eq 40 ]] && { echo "❌ MySQL not listening"; docker logs --tail=120 solace_mysql || true; exit 1; }
done
echo "   MySQL is listening."

# --- Root connectivity / create grants for app user ---
echo "==> Verifying MySQL root connectivity"
if [[ -z "${MYSQL_ROOT_PASSWORD:-}" ]]; then
  echo "⚠️  MYSQL_ROOT_PASSWORD not set in .env; attempting without it (Ubuntu local no-root-pass won't work inside container)."
fi

ROOT_ARGS=(-h 127.0.0.1 -P 3306 -uroot)
[[ -n "${MYSQL_ROOT_PASSWORD:-}" ]] && ROOT_ARGS+=(-p"$MYSQL_ROOT_PASSWORD")

if ! mysql "${ROOT_ARGS[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
  echo "❌ Cannot connect as MySQL root. Check MYSQL_ROOT_PASSWORD in .env and container logs."
  docker logs --tail=120 solace_mysql || true
  exit 1
fi
echo "   Root OK."

APP_USER="${MYSQL_USER:-solace_app}"
APP_PASS="${MYSQL_PASSWORD:?MYSQL_PASSWORD missing in .env}"
APP_DB="${MYSQL_DB:-solace}"

echo "==> Ensuring user '${APP_USER}'@'%' exists with access to '${APP_DB}'"
mysql "${ROOT_ARGS[@]}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${APP_DB}\`;
CREATE USER IF NOT EXISTS '${APP_USER}'@'%' IDENTIFIED BY '${APP_PASS}';
ALTER USER '${APP_USER}'@'%' IDENTIFIED BY '${APP_PASS}';
GRANT ALL PRIVILEGES ON \`${APP_DB}\`.* TO '${APP_USER}'@'%';
FLUSH PRIVILEGES;
SQL
echo "   Grants ensured."

# --- App user sanity test ---
echo "==> Testing MySQL app user login"
if mysql --protocol=TCP -h 127.0.0.1 -P 3306 -u"$APP_USER" -p"$APP_PASS" -e "USE \`${APP_DB}\`; SELECT 1;" >/dev/null 2>&1; then
  echo "   ✅ MySQL app user OK."
else
  echo "   ❌ MySQL app user test failed. Listing users/hosts:"
  mysql "${ROOT_ARGS[@]}" -e "SELECT user,host FROM mysql.user;"
  exit 1
fi

# --- Redis check (optional if redis-cli installed) ---
echo "==> Redis check"
if command -v redis-cli >/dev/null 2>&1; then
  if [[ -n "${REDIS_PASSWORD:-}" ]]; then
    if redis-cli -a "$REDIS_PASSWORD" PING >/dev/null 2>&1; then
      echo "   ✅ Redis PING OK."
    else
      echo "   ❌ Redis PING failed. Check REDIS_PASSWORD and container logs."
      docker logs --tail=120 solace_redis || true
    fi
  else
    echo "   ⚠️  REDIS_PASSWORD not set in .env (container likely unauthenticated)."
    redis-cli PING || true
  fi
else
  echo "   (redis-cli not installed; skip)   Hint: sudo apt install -y redis-tools"
fi

# --- Weaviate readiness ---
echo "==> Weaviate readiness"
W_READY_URL="http://127.0.0.1:8080/v1/.well-known/ready"
W_LIVE_URL="http://127.0.0.1:8080/v1/.well-known/live"
CURL_OPTS=(-fsS)
if [[ -n "${WEAVIATE_APIKEY:-}" ]]; then
  CURL_OPTS+=(-H "Authorization: Bearer ${WEAVIATE_APIKEY}")
fi

READY_OUT="$(curl "${CURL_OPTS[@]}" "$W_READY_URL" || true)"
LIVE_OUT="$(curl "${CURL_OPTS[@]}" "$W_LIVE_URL" || true)"

if [[ -n "$READY_OUT" && -n "$LIVE_OUT" ]]; then
  echo "   ✅ Weaviate ready/live:"
  echo "      /ready: $READY_OUT"
  echo "      /live : $LIVE_OUT"
else
  echo "   ❌ Weaviate not ready; last 80 log lines:"
  docker logs --tail=80 solace_weaviate || true
fi

echo "✅ Core bring-up + DB grants complete."

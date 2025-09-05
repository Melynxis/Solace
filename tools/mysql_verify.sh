# /home/melynxis/solace/tools/mysql_verify.sh
#!/usr/bin/env bash
set -euo pipefail

BASE="/home/melynxis/solace"
ENV_FILE="$BASE/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
else
  echo "ERROR: $ENV_FILE not found (need MYSQL_ROOT_PASSWORD at least)"; exit 1
fi

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:?Missing in .env}"

echo "[1/3] Waiting for 'solace_mysql' health..."
tries=60
until docker inspect -f '{{.State.Health.Status}}' solace_mysql 2>/dev/null | grep -q healthy; do
  ((tries--)) || { echo "MySQL did not become healthy in time"; exit 1; }
  sleep 2
done
echo "  - healthy"

echo "[2/3] Verifying root with TCP (no socket)..."
docker exec -i solace_mysql mysql -h 127.0.0.1 -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 'root_ok' AS ok;"

echo "[3/3] Verifying app user (if present)..."
APP_USER="${MYSQL_USER:-solace_app}"
APP_PW="${MYSQL_PASSWORD:-}"
if [[ -n "$APP_PW" ]]; then
  docker exec -i solace_mysql mysql -h 127.0.0.1 -u"${APP_USER}" -p"${APP_PW}" -e "SHOW DATABASES LIKE '${MYSQL_DB:-solace}';"
else
  echo "  - Skipping app user check (MYSQL_PASSWORD not set in .env)"
fi

echo "✅ MySQL verification passed."

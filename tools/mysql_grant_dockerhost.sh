# /home/melynxis/solace/tools/mysql_grant_dockerhost.sh
#!/usr/bin/env bash
set -euo pipefail

BASE="/home/melynxis/solace"
ENV_FILE="$BASE/.env"

# load env
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${MYSQL_ROOT_PASSWORD:?Missing in .env}"
: "${MYSQL_DB:?Missing in .env}"
: "${MYSQL_USER:?Missing in .env}"
: "${MYSQL_PASSWORD:?Missing in .env}"

DOCKER_HOST_PATTERN="${DOCKER_HOST_PATTERN:-172.18.%}"  # default bridge

echo "[1/2] Creating/updating app user for Docker host pattern ${DOCKER_HOST_PATTERN}..."
docker exec -i solace_mysql mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" <<SQL
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'${DOCKER_HOST_PATTERN}' IDENTIFIED BY '${MYSQL_PASSWORD}';
ALTER USER '${MYSQL_USER}'@'${DOCKER_HOST_PATTERN}' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DB}\`.* TO '${MYSQL_USER}'@'${DOCKER_HOST_PATTERN}';
FLUSH PRIVILEGES;
SQL

echo "[2/2] Showing grants for ${MYSQL_USER}..."
docker exec -i solace_mysql mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW GRANTS FOR '${MYSQL_USER}'@'${DOCKER_HOST_PATTERN}';"
echo "✅ Grants in place for ${MYSQL_USER}@${DOCKER_HOST_PATTERN}"

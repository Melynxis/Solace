#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/home/melynxis/solace/.env"

# Load .env if present
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo "ERROR: $ENV_FILE not found"
  exit 1
fi

# Default query if not provided
QUERY="${1:-SHOW TABLES;}"
DB="${MYSQL_DB:-solace}"
USER="${MYSQL_USER:-solace_app}"
PW="${MYSQL_PASSWORD:-solace_app_pwd}"
HOST="${MYSQL_HOST:-127.0.0.1}"
PORT="${MYSQL_PORT:-3306}"

mysql -h "$HOST" -P "$PORT" -u "$USER" -p"$PW" -D "$DB" -e "$QUERY"

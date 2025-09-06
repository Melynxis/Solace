# /home/melynxis/solace/tools/mysql_fix_root127.sh
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
  echo "ERROR: $ENV_FILE not found (need MYSQL_ROOT_PASSWORD)"; exit 1
fi

: "${MYSQL_ROOT_PASSWORD:?Missing MYSQL_ROOT_PASSWORD in .env}"

echo "[1/2] Granting admin privileges to root@127.0.0.1 using socket (root@localhost)..."
docker exec -i solace_mysql mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" <<'SQL'
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
GRANT SYSTEM_USER ON *.* TO 'root'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

echo "[2/2] Show grants for root@127.0.0.1..."
docker exec -i solace_mysql mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW GRANTS FOR 'root'@'127.0.0.1';"

echo "✅ root@127.0.0.1 now has admin privileges."

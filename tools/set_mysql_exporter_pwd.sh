# /home/melynxis/solace/tools/set_mysql_exporter_pwd.sh
#!/usr/bin/env bash
set -euo pipefail

BASE="/home/melynxis/solace"
ENV_FILE="$BASE/.env"
CNF_FILE="$BASE/infra/mysqld_exporter.my.cnf"
COMPOSE="$BASE/infra/exporters.compose.yml"

# Load .env for root password
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
else
  echo "ERROR: $ENV_FILE not found (need MYSQL_ROOT_PASSWORD)"; exit 1
fi
: "${MYSQL_ROOT_PASSWORD:?Missing MYSQL_ROOT_PASSWORD in .env}"

# Read new password (arg or prompt)
NEW_PW="${1:-}"
if [[ -z "$NEW_PW" ]]; then
  read -r -s -p "Enter NEW exporter password: " NEW_PW
  echo
fi

echo "[1/4] Setting MySQL 'exporter' user password..."
docker exec -i solace_mysql mysql -h 127.0.0.1 -uroot -p"${MYSQL_ROOT_PASSWORD}" <<SQL
CREATE USER IF NOT EXISTS 'exporter'@'%' IDENTIFIED BY '${NEW_PW}';
ALTER USER 'exporter'@'%' IDENTIFIED BY '${NEW_PW}';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';
FLUSH PRIVILEGES;
SQL

echo "[2/4] Updating $CNF_FILE ..."
if [[ ! -f "$CNF_FILE" ]]; then
  mkdir -p "$(dirname "$CNF_FILE")"
  touch "$CNF_FILE"
fi
cat > "$CNF_FILE" <<EOF
[client]
user=exporter
password=${NEW_PW}
host=127.0.0.1
port=3306
EOF
chmod 600 "$CNF_FILE"

echo "[3/4] Restarting exporters stack..."
docker compose -f "$COMPOSE" up -d

echo "[4/4] Verifying mysqld_exporter ..."
sleep 5
curl -fsS http://127.0.0.1:9104/metrics | head -n 10 || {
  echo "mysqld_exporter not responding; check logs:";
  echo "  docker logs --tail=200 solace_mysqld_exporter";
  exit 1
}
echo "✅ mysqld_exporter responding on :9104"

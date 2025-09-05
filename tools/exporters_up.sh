# /home/melynxis/solace/tools/exporters_up.sh
#!/usr/bin/env bash
set -euo pipefail

BASE="/home/melynxis/solace"
ENV_FILE="$BASE/.env"
SUBNET_CIDR="${SUBNET_CIDR:-192.168.1.0/24}"
MYSQL_ROOT_PASSWORD_DEFAULT="solace_root_pwd"
MYSQL_EXPORTER_PASSWORD="${MYSQL_EXPORTER_PASSWORD:-exporter_pwd}"

# Load env if present (brings in REDIS_PASSWORD, MYSQL_ROOT_PASSWORD, etc.)
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
else
  echo "WARN: $ENV_FILE not found. Proceeding with defaults/env."
fi

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-$MYSQL_ROOT_PASSWORD_DEFAULT}"

echo "[1/5] Ensure MySQL exporter user exists (inside container)..."
docker exec -i solace_mysql mysql -h 127.0.0.1 -uroot -p"${MYSQL_ROOT_PASSWORD}" <<SQL
CREATE USER IF NOT EXISTS 'exporter'@'%' IDENTIFIED BY '${MYSQL_EXPORTER_PASSWORD}';
ALTER USER 'exporter'@'%' IDENTIFIED BY '${MYSQL_EXPORTER_PASSWORD}';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';
FLUSH PRIVILEGES;
SQL

echo "[2/5] Starting exporters (node:9100, mysql:9104, redis:9121, blackbox:9115)..."
docker compose --project-directory "/home/melynxis/solace" --env-file "/home/melynxis/solace/.env" -f "$BASE/infra/exporters.compose.yml" up -d

echo "[3/5] UFW — allow only ${SUBNET_CIDR} ..."
sudo ufw allow from "${SUBNET_CIDR}" to any port 9100 comment 'node_exporter'
sudo ufw allow from "${SUBNET_CIDR}" to any port 9104 comment 'mysqld_exporter'
sudo ufw allow from "${SUBNET_CIDR}" to any port 9121 comment 'redis_exporter'
sudo ufw allow from "${SUBNET_CIDR}" to any port 9115 comment 'blackbox_exporter'

echo "[4/5] Local health checks ..."
curl -fsS http://127.0.0.1:9100/metrics >/dev/null && echo "- node_exporter OK"
curl -fsS http://127.0.0.1:9104/metrics >/dev/null && echo "- mysqld_exporter OK" || echo "- mysqld_exporter not ready yet"
curl -fsS http://127.0.0.1:9121/metrics >/dev/null && echo "- redis_exporter OK" || echo "- redis_exporter not ready yet"
curl -fsS "http://127.0.0.1:9115/probe?module=http_2xx&target=http://127.0.0.1:8080/v1/.well-known/ready" >/dev/null \
  && echo "- blackbox_exporter OK" || echo "- blackbox_exporter probe not ready yet"

echo "[5/5] Reminder: configure Prometheus on the Observability host:"
cat <<'HINT'

- job_name: 'solace-node'
  static_configs: [ { targets: ['SOLACE_IP:9100'] } ]

- job_name: 'solace-mysql'
  static_configs: [ { targets: ['SOLACE_IP:9104'] } ]

- job_name: 'solace-redis'
  static_configs: [ { targets: ['SOLACE_IP:9121'] } ]

- job_name: 'solace-blackbox'
  metrics_path: /probe
  params: { module: [http_2xx] }
  static_configs:
    - targets: ['http://SOLACE_IP:8080/v1/.well-known/ready']
  relabel_configs:
    - { source_labels: [__address__], target_label: __param_target }
    - { source_labels: [__param_target], target_label: instance }
    - { target_label: __address__, replacement: SOLACE_IP:9115 }
HINT

echo "✅ Exporters ready."

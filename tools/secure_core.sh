# /home/melynxis/solace/tools/secure_core.sh
#!/usr/bin/env bash
set -euo pipefail

BASE="/home/melynxis/solace"
ENV_FILE="$BASE/.env"

# ====== INPUTS ======
# Provide your final secrets via environment or you'll be prompted.
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
MYSQL_APP_PASSWORD="${MYSQL_APP_PASSWORD:-}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
WEAVIATE_APIKEY="${WEAVIATE_APIKEY:-}"
MYSQL_DB="${MYSQL_DB:-solace}"
MYSQL_USER="${MYSQL_USER:-solace_app}"
SUBNET_CIDR="${SUBNET_CIDR:-192.168.1.0/24}"
SUBNET_MYSQL_HOSTPATTERN="${SUBNET_MYSQL_HOSTPATTERN:-192.168.1.%}"

# Current/temporary root password used to connect BEFORE rotation:
CURRENT_ROOT_PASSWORD="${CURRENT_ROOT_PASSWORD:-solace_root_pwd}"

prompt_if_empty () {
  local varname="$1" prompt="$2"
  if [[ -z "${!varname}" ]]; then
    read -r -s -p "$prompt: " value
    echo
    export "$varname"="$value"
  fi
}

prompt_if_empty MYSQL_ROOT_PASSWORD "Enter NEW MySQL root password"
prompt_if_empty MYSQL_APP_PASSWORD  "Enter NEW MySQL app user password for ${MYSQL_USER}"
prompt_if_empty REDIS_PASSWORD      "Enter NEW Redis password"
prompt_if_empty WEAVIATE_APIKEY     "Enter NEW Weaviate API key (single key)"

echo "[1/8] Writing/updating $ENV_FILE ..."
# create .env with final values (idempotent)
cat > "$ENV_FILE" <<ENV
# ==== Solace .env (HARDENED) ====
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_DB=${MYSQL_DB}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_APP_PASSWORD}

# Redis
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_URL=redis://:$(printf '%s' "${REDIS_PASSWORD}" | sed 's|/|%2F|g')@127.0.0.1:6379

# Registry API
REGISTRY_PORT=8081

# Weaviate auth
WEAVIATE_APIKEY=${WEAVIATE_APIKEY}

# Observability (example; adjust as needed)
# OBSERVABILITY_HOST=192.0.2.10
# PUSHGATEWAY_URL=http://192.0.2.10:9091
ENV

echo "[2/8] Securing MySQL users/grants inside container ..."
# ensure mysql is up
docker ps --format '{{.Names}}' | grep -q '^solace_mysql$' || { echo "MySQL container not running."; exit 1; }

docker exec -i solace_mysql mysql -uroot -p"${CURRENT_ROOT_PASSWORD}" <<SQL
-- Rotate root passwords; keep root local only
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
-- Revoke remote root if exists
DROP USER IF EXISTS 'root'@'%';

-- Ensure DB exists
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DB}\`;

-- Create/update app users for local + subnet access
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_APP_PASSWORD}';
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_APP_PASSWORD}';
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'${SUBNET_MYSQL_HOSTPATTERN}' IDENTIFIED BY '${MYSQL_APP_PASSWORD}';

ALTER USER '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_APP_PASSWORD}';
ALTER USER '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_APP_PASSWORD}';
ALTER USER '${MYSQL_USER}'@'${SUBNET_MYSQL_HOSTPATTERN}' IDENTIFIED BY '${MYSQL_APP_PASSWORD}';

GRANT ALL PRIVILEGES ON \`${MYSQL_DB}\`.* TO '${MYSQL_USER}'@'localhost';
GRANT ALL PRIVILEGES ON \`${MYSQL_DB}\`.* TO '${MYSQL_USER}'@'127.0.0.1';
GRANT ALL PRIVILEGES ON \`${MYSQL_DB}\`.* TO '${MYSQL_USER}'@'${SUBNET_MYSQL_HOSTPATTERN}';
FLUSH PRIVILEGES;
SQL

echo "[3/8] Setting Redis password (runtime) ..."
# set at runtime so it's effective immediately
docker exec -i solace_redis redis-cli CONFIG SET requirepass "${REDIS_PASSWORD}" >/dev/null
docker exec -i solace_redis redis-cli -a "${REDIS_PASSWORD}" ACL SETUSER default on ">${REDIS_PASSWORD}" allchannels allkeys allcommands >/dev/null

echo "[4/8] Persist Redis password in compose ..."
# add/replace --requirepass in the compose file
COMPOSE_CORE="$BASE/infra/compose.core.yml"
if grep -q 'redis-server' "$COMPOSE_CORE"; then
  # Replace redis command line ensuring --requirepass is present (idempotent)
  awk '
    BEGIN{printed=0}
    /redis-server/ && printed==0{
      print "    command: [\"redis-server\", \"--save\", \"60\", \"1\", \"--loglevel\", \"warning\", \"--requirepass\", \"${REDIS_PASSWORD}\"]"
      printed=1; skip=1; next
    }
    /^    command:/ && printed==1 && skip==1 { next }
    { print }
  ' "$COMPOSE_CORE" > "${COMPOSE_CORE}.tmp" && mv "${COMPOSE_CORE}.tmp" "$COMPOSE_CORE"
fi

echo "[5/8] Enabling Weaviate API key auth (and disabling anonymous) ..."
# patch Weaviate env vars in compose
if grep -q 'weaviate:' "$COMPOSE_CORE"; then
  # ensure the env block has the required keys
  python3 - "$COMPOSE_CORE" <<'PY'
import sys, re
p=sys.argv[1]
txt=open(p).read()
def ensure(k,v):
    pattern = rf'^\s+{re.escape(k)}:\s*".*"$'
    if re.search(pattern, txt, flags=re.M):
        return re.sub(pattern, f'      {k}: "{v}"', txt, flags=re.M)
    # insert under environment: block
    return re.sub(r'(\s+environment:\n)', r'\1      '+k+': "'+v+'"\n', txt, count=1, flags=re.M)

txt = ensure("AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED","false")
txt = ensure("AUTHENTICATION_APIKEY_ENABLED","true")
txt = ensure("AUTHENTICATION_APIKEY_ALLOWED_KEYS","${WEAVIATE_APIKEY}")
txt = ensure("AUTHENTICATION_APIKEY_USERS","solace")
open(p,"w").write(txt)
PY
fi

echo "[6/8] Restarting core containers to apply config ..."
docker compose -f "$COMPOSE_CORE" up -d

echo "[7/8] UFW rules — allow only ${SUBNET_CIDR} to MySQL/Redis/Weaviate ..."
sudo ufw allow from "${SUBNET_CIDR}" to any port 3306 comment 'MySQL (Solace)'
sudo ufw allow from "${SUBNET_CIDR}" to any port 6379 comment 'Redis (Solace)'
sudo ufw allow from "${SUBNET_CIDR}" to any port 8080 comment 'Weaviate (Solace)'
# remove broad allows if they exist (best-effort)
sudo ufw deny 3306/tcp || true
sudo ufw deny 6379/tcp || true
sudo ufw deny 8080/tcp || true

echo "[8/8] Verifying ..."
echo "- MySQL root (localhost) quick check"
docker exec -i solace_mysql mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 'root_ok' as ok;" || { echo "MySQL root check failed"; exit 1; }

echo "- Redis AUTH check"
docker exec -i solace_redis redis-cli -a "${REDIS_PASSWORD}" PING | grep -q PONG || { echo "Redis auth failed"; exit 1; }

echo "- Weaviate readiness (with API key)"
curl -fsS -H "X-API-KEY: ${WEAVIATE_APIKEY}" http://127.0.0.1:8080/v1/.well-known/ready >/dev/null || { echo "Weaviate ready check failed"; exit 1; }

echo
echo "✅ Security hardening applied."
echo "Saved env: $ENV_FILE"
echo "NOTE: MySQL app user '${MYSQL_USER}' is allowed from hosts: localhost, 127.0.0.1, and ${SUBNET_MYSQL_HOSTPATTERN}"

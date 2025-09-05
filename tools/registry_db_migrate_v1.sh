# /home/melynxis/solace/tools/registry_db_migrate_v1.sh
#!/usr/bin/env bash
set -euo pipefail

BASE="/home/melynxis/solace"
ENV_FILE="$BASE/.env"

# load env for MySQL creds
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${MYSQL_ROOT_PASSWORD:?Missing in .env}"
: "${MYSQL_DB:?Missing in .env}"

echo "[1/2] Applying DB changes to ${MYSQL_DB} …"
docker exec -i solace_mysql mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DB}" <<'SQL'
-- 1) Events/audit table for lifecycle transitions and noteworthy actions
CREATE TABLE IF NOT EXISTS spirit_events (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  spirit_id BIGINT UNSIGNED NOT NULL,
  event_type ENUM('create','state_change','meta_update','name_update','error') NOT NULL,
  prev_state ENUM('pending','created','ready','error') NULL,
  new_state  ENUM('pending','created','ready','error') NULL,
  note VARCHAR(1024) NULL,
  meta JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_spirit_events_spirit_id (spirit_id),
  CONSTRAINT fk_spirit_events_spirit
    FOREIGN KEY (spirit_id) REFERENCES spirits(id)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2) Extra index for listing/filtering
CREATE INDEX IF NOT EXISTS idx_spirits_updated_at ON spirits(updated_at);
SQL

echo "[2/2] Quick verify …"
docker exec -i solace_mysql mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "USE ${MYSQL_DB}; SHOW TABLES LIKE 'spirit_events'; SHOW INDEX FROM spirits LIKE 'idx_spirits_updated_at';"

echo "✅ Migration v1 applied."

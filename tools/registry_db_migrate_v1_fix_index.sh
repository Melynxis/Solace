# /home/melynxis/solace/tools/registry_db_migrate_v1_fix_index.sh
#!/usr/bin/env bash
set -euo pipefail

BASE="/home/melynxis/solace"
ENV_FILE="$BASE/.env"

# load MySQL env
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${MYSQL_ROOT_PASSWORD:?Missing in .env}"
: "${MYSQL_DB:?Missing in .env}"

echo "[1/2] Creating idx_spirits_updated_at if missing …"
docker exec -i solace_mysql mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DB}" <<'SQL'
-- Only create the index if it doesn't already exist
SET @idx_exists := (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'spirits'
    AND INDEX_NAME = 'idx_spirits_updated_at'
);
SET @sql := IF(@idx_exists = 0,
  'CREATE INDEX idx_spirits_updated_at ON spirits(updated_at)',
  'SELECT "idx_spirits_updated_at already exists"');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
SQL

echo "[2/2] Verify …"
docker exec -i solace_mysql mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "USE ${MYSQL_DB}; SHOW INDEX FROM spirits WHERE Key_name='idx_spirits_updated_at';"

echo "✅ Index fix applied."

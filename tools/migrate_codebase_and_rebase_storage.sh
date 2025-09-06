#!/usr/bin/env bash
set -euo pipefail

# === SETTINGS / CONSTANTS ===
USER_NAME="melynxis"
USER_GROUP="melynxis"

BASE="/home/${USER_NAME}/solace"
INFRA_DIR="${BASE}/infra"
CORE_COMPOSE="${INFRA_DIR}/compose.core.yml"
EXPORTERS_COMPOSE="${INFRA_DIR}/exporters.compose.yml"

# Labeled disks / target mountpoints (from your audit)
CODEBASE_LABEL="SOLACE_CODEBASE"   # currently /dev/sdb1 mounted at /mnt/codebase
MYSQL_DIR="/var/lib/mysql"         # SOLACE_MYSQL
WEAVIATE_DIR="/var/lib/weaviate"   # SOLACE_WEAVIATE
REDIS_DIR="/home/${USER_NAME}/run/redis" # on SOLACE_RUN

# Named volumes used by compose
MYSQL_VOL="solace-core_mysql_data"
WEAV_VOL="solace-core_weaviate_data"

# Backups
TS="$(date +%s)"
BK_ROOT="/home/${USER_NAME}/run/backups"
BK_VOLS="${BK_ROOT}/volumes.${TS}"
BK_ETC="${BK_ROOT}/etc.${TS}"

# Scratch / staging on the CODEBASE disk
STAGING_NAME="_incoming_solace_sync_${TS}"

# === FUNCTIONS ===
need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }; }

get_uuid_by_label() {
  local label="$1"
  blkid -L "$label" 2>/dev/null || true
}

ensure_dir_owned() {
  local path="$1" uidgid="$2"
  sudo mkdir -p "$path"
  sudo chown -R "$uidgid" "$path"
}

docker_down_if_exists() {
  local file="$1"
  if [[ -f "$file" ]]; then
    echo ">> docker compose down: $file"
    docker compose -f "$file" down || true
  fi
}

backup_volume() {
  local vol="$1"
  if docker volume inspect "$vol" >/dev/null 2>&1; then
    echo "   - backing up volume $vol -> $BK_VOLS/$vol.tgz"
    docker run --rm -v "$vol":/from -v "$BK_VOLS":/to alpine sh -c "cd /from && tar -czf /to/${vol}.tgz . || true"
    echo "   - removing volume $vol"
    docker volume rm "$vol" || true
  else
    echo "   - volume $vol not present (skip)"
  fi
}

recreate_bind_volume() {
  local vol="$1" host_dir="$2"
  echo "   - creating volume $vol as bind to $host_dir"
  docker volume create --driver local -o type=none -o o=bind -o device="$host_dir" "$vol" >/dev/null
}

# === PREFLIGHT ===
echo "=== PRE-FLIGHT CHECKS ==="
for c in rsync jq awk sed grep cut curl; do need_cmd "$c"; done
need_cmd docker
need_cmd blkid
need_cmd lsblk

CODEBASE_DEV="$(get_uuid_by_label "$CODEBASE_LABEL")"
if [[ -z "$CODEBASE_DEV" ]]; then
  echo "ERROR: Could not resolve device for label ${CODEBASE_LABEL}. Check 'lsblk -f' / 'blkid'." >&2
  exit 1
fi
echo "CODEBASE device: $CODEBASE_DEV (label=${CODEBASE_LABEL})"

echo "Creating backup directories..."
ensure_dir_owned "$BK_VOLS" "${USER_NAME}:${USER_GROUP}"
ensure_dir_owned "$BK_ETC"  "${USER_NAME}:${USER_GROUP}"

# === STOP STACKS ===
echo "=== STOPPING DOCKER STACKS ==="
docker_down_if_exists "$CORE_COMPOSE"
docker_down_if_exists "$EXPORTERS_COMPOSE"

# === COPY CURRENT CODEBASE TO CODEBASE DISK (STAGING) ===
echo "=== STAGING CURRENT ${BASE} TO CODEBASE DISK ==="
# Make sure CODEBASE device is mounted somewhere; if it's at /mnt/codebase (per audit), great; if not, mount it temporarily.
MOUNT_POINT_TMP="/mnt/codebase"
if ! mount | grep -q "on ${MOUNT_POINT_TMP} "; then
  echo "Mounting ${CODEBASE_DEV} at ${MOUNT_POINT_TMP} (temporary)..."
  sudo mkdir -p "$MOUNT_POINT_TMP"
  sudo mount "$CODEBASE_DEV" "$MOUNT_POINT_TMP"
fi

STAGING_DIR="${MOUNT_POINT_TMP}/${STAGING_NAME}"
echo "Staging to: $STAGING_DIR"
sudo mkdir -p "$STAGING_DIR"
sudo rsync -aHAX --numeric-ids --info=progress2 \
  --exclude '.venv' \
  --exclude 'node_modules' \
  "$BASE"/ "$STAGING_DIR"/

# === FSTAB: REMAP CODEBASE DISK TO /home/.../solace ===
echo "=== REMAPPING CODEBASE DISK TO ${BASE} (fstab + mount) ==="
# Backup fstab
sudo cp -a /etc/fstab "${BK_ETC}/fstab.${TS}.bak"

# Remove any existing /mnt/codebase fstab line for this device
# and insert a new line mounting it at $BASE
UUID_LINE="$(blkid -s UUID -o value "$CODEBASE_DEV" || true)"
if [[ -z "$UUID_LINE" ]]; then
  echo "ERROR: Unable to obtain UUID for ${CODEBASE_DEV}" >&2
  exit 1
fi

# Remove old entries for /mnt/codebase or the same UUID
sudo sed -i.bak "/${CODEBASE_LABEL}/d" /etc/fstab || true
sudo sed -i "/${UUID_LINE//\//\\/}/d" /etc/fstab || true
sudo sed -i "/[[:space:]]\/mnt\/codebase[[:space:]]/d" /etc/fstab || true

# Add new entry
echo "UUID=${UUID_LINE}  ${BASE}  ext4  defaults,noatime  0  2" | sudo tee -a /etc/fstab >/dev/null

# Unmount old /mnt/codebase, prepare BASE mountpoint
if mount | grep -q "on ${MOUNT_POINT_TMP} "; then
  echo "Unmounting ${MOUNT_POINT_TMP}..."
  sudo umount "$MOUNT_POINT_TMP"
fi

# Backup existing BASE dir and mount disk there
if mount | grep -q "on ${BASE} "; then
  echo "Already mounted at ${BASE} (skipping mount)."
else
  if [[ -d "$BASE" ]]; then
    echo "Backing up existing ${BASE} to ${BASE}.pre-mount.${TS}"
    sudo mv "$BASE" "${BASE}.pre-mount.${TS}"
  fi
  sudo mkdir -p "$BASE"
  echo "Mounting ${CODEBASE_DEV} at ${BASE}..."
  sudo mount "$BASE"
fi

# === MOVE STAGING INTO PLACE (on the disk now mounted at $BASE) ===
if [[ -d "${BASE}/${STAGING_NAME}" ]]; then
  echo "Promoting staged content into ${BASE}..."
  # Move contents up (including dotfiles)
  sudo bash -c "shopt -s dotglob nullglob; mv '${BASE}/${STAGING_NAME}/'* '${BASE}/' || true"
  sudo rmdir "${BASE}/${STAGING_NAME}" || true
else
  echo "WARNING: staging directory not found at ${BASE}/${STAGING_NAME}; skipping promote."
fi

# Ensure ownership for user
echo "Fixing ownership on ${BASE}..."
sudo chown -R "${USER_NAME}:${USER_GROUP}" "$BASE"

# === REBASE DOCKER VOLUMES TO DESIGNATED DISKS ===
echo "=== REBASING DOCKER VOLUMES ==="
ensure_dir_owned "$MYSQL_DIR" "999:999"         || true
ensure_dir_owned "$WEAVIATE_DIR" "1001:1001"    || true
ensure_dir_owned "$REDIS_DIR"  "${USER_NAME}:${USER_GROUP}"

echo "Backing up and removing named volumes (if present)..."
mkdir -p "$BK_VOLS"
backup_volume "$MYSQL_VOL"
backup_volume "$WEAV_VOL"

echo "Re-creating volumes as bind volumes..."
recreate_bind_volume "$MYSQL_VOL" "$MYSQL_DIR"
recreate_bind_volume "$WEAV_VOL"  "$WEAVIATE_DIR"

# Create an override for Redis bind mount (if exporters/core file doesn’t already do it)
OVR="${INFRA_DIR}/compose.core.override.yml"
echo "Writing Redis override compose to ${OVR}"
cat > "$OVR" <<YAML
services:
  redis:
    volumes:
      - ${REDIS_DIR}:/data
YAML

# === START STACKS ===
echo "=== STARTING DOCKER STACKS ==="
if [[ -f "$CORE_COMPOSE" ]]; then
  docker compose -f "$CORE_COMPOSE" -f "$OVR" up -d
fi
if [[ -f "$EXPORTERS_COMPOSE" ]]; then
  docker compose -f "$EXPORTERS_COMPOSE" up -d
fi

# === VERIFY ===
echo "=== VERIFYING MOUNTS ==="
for c in solace_mysql solace_weaviate solace_redis; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$c"; then
    echo "[$c] mounts:"
    docker inspect "$c" --format '{{json .Mounts}}' | jq -r '.[] | "  - " + (.Source + " -> " + .Destination)'
  fi
done

echo "=== QUICK HEALTH ==="
# MySQL ping
if [[ -f "${BASE}/.env" ]]; then
  ROOTPW="$(. "${BASE}/.env"; echo "${MYSQL_ROOT_PASSWORD:-}")"
  if [[ -n "$ROOTPW" ]]; then
    echo "- MySQL:"
    docker exec -i solace_mysql mysql -uroot -p"$ROOTPW" -e "SELECT 1;" >/dev/null && echo "  ok" || echo "  FAIL"
  fi
fi

echo "- Weaviate readiness:"
curl -fsS http://127.0.0.1:8080/v1/.well-known/ready || echo "  not ready"

echo "- Redis INFO persistence:"
if [[ -f "${BASE}/.env" ]]; then
  REDISPW="$(. "${BASE}/.env"; echo "${REDIS_PASSWORD:-}")"
  if [[ -n "$REDISPW" ]]; then
    docker exec -i solace_redis redis-cli -a "$REDISPW" INFO persistence | grep -E 'loading|aof_enabled|rdb_' | sed 's/^/  /'
  fi
fi

echo "=== DONE ==="
echo "Backups:"
echo "  - fstab backup: ${BK_ETC}"
echo "  - volume archives: ${BK_VOLS}"

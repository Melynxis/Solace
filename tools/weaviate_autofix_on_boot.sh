#!/usr/bin/env bash
# weaviate_autofix_on_boot.sh
# Self-heals common single-node issues: Raft join-loops and readyness/auth drift.

set -euo pipefail

INFRA_DIR="/home/melynxis/solace/infra"
ENV_FILE="/home/melynxis/solace/.env"
SERVICE_NAME="solace_weaviate"
DATA_DIR="/var/lib/weaviate"           # bind-mounted path
RAFT_DIR="${DATA_DIR}/raft"
READY_URL="http://127.0.0.1:8080/v1/.well-known/ready"
SCHEMA_URL="http://127.0.0.1:8080/v1/schema"

log(){ printf "[weaviate-autofix] %s\n" "$*"; }

# Helper: curl code
http_code() {
  curl -s -o /dev/null -w "%{http_code}" "$1" || true
}

# 0) Bring Weaviate up (compose will create it if needed)
log "Ensuring Weaviate container is started…"
docker compose --env-file "$ENV_FILE" -f "${INFRA_DIR}/compose.core.yml" up -d weaviate >/dev/null

# 1) Wait up to 60s for /ready
for i in $(seq 1 60); do
  code=$(http_code "$READY_URL")
  [ "$code" = "200" ] && { log "/ready OK (200)"; break; }
  sleep 1
done

# If still not ready, check logs for a join loop and auto-fix raft
code=$(http_code "$READY_URL")
if [ "$code" != "200" ]; then
  log "/ready not 200 (got $code). Inspecting logs for join-loop…"
  if docker logs --tail=300 "$SERVICE_NAME" 2>&1 | grep -q 'status":8'; then
    log "Join-loop detected (status:8). Nuking ONLY Raft state and restarting…"
    # Stop service (just Weaviate)
    docker compose -f "${INFRA_DIR}/compose.core.yml" stop weaviate >/dev/null || true

    # Ensure the bind mount is not busy; if it is, lazy umount the mountpoint (rare)
    if mountpoint -q "$DATA_DIR"; then
      log "$DATA_DIR is a mountpoint; attempting lazy umount to release handles (safe) …"
      sudo umount -l "$DATA_DIR" || true
      # Recreate the dir in case umount hid it
      sudo mkdir -p "$DATA_DIR"
    fi

    # Remove ONLY raft (preserve objects/schema)
    if [ -d "$RAFT_DIR" ]; then
      log "Removing ${RAFT_DIR}…"
      sudo rm -rf "$RAFT_DIR"
    fi

    # Restart Weaviate
    docker compose --env-file "$ENV_FILE" -f "${INFRA_DIR}/compose.core.yml" up -d weaviate >/dev/null

    # Wait again for readiness
    for i in $(seq 1 60); do
      code=$(http_code "$READY_URL")
      [ "$code" = "200" ] && { log "Recovered: /ready OK (200) after raft reset."; break; }
      sleep 1
    done
  else
    log "No join-loop signature found. Leaving container up; please check logs manually."
  fi
fi

# 2) Light auth sanity:
# Prefer X-API-KEY for your build; Bearer is allowed to 401.
WEAVIATE_APIKEY="$(
  awk -F= '/^WEAVIATE_APIKEY=/{print substr($0, index($0,$2))}' "$ENV_FILE" 2>/dev/null || true
)"
WEAVIATE_APIKEY="${WEAVIATE_APIKEY:-}"

if [ -n "$WEAVIATE_APIKEY" ]; then
  # X-API-KEY (expected 200)
  xcode=$(curl -s -H "X-API-KEY: $WEAVIATE_APIKEY" -o /dev/null -w "%{http_code}" "$SCHEMA_URL" || true)
  if [ "$xcode" = "200" ]; then
    log "/schema 200 with X-API-KEY (good)."
  else
    log "WARN: /schema not 200 with X-API-KEY (got $xcode). Dumping 2 lines of context:"
    curl -s -i -H "X-API-KEY: $WEAVIATE_APIKEY" "$SCHEMA_URL" | sed -n '1,8p'
  fi
else
  log "NOTE: WEAVIATE_APIKEY is empty; auth check skipped."
fi

log "Autofix run complete."

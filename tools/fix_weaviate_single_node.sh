#!/usr/bin/env bash
set -euo pipefail

BASE="/home/melynxis/solace"
CORE="${BASE}/infra/compose.core.yml"
OVR="${BASE}/infra/compose.core.override.yml"
ENVF="${BASE}/.env"

# Extend the existing override to force single-node Weaviate
# (we leave other services untouched)
cat > "$OVR" <<'YAML'
services:
  mysql:
    volumes:
      - /var/lib/mysql:/var/lib/mysql

  weaviate:
    volumes:
      - /var/lib/weaviate:/var/lib/weaviate
    environment:
      # Force standalone (no raft/cluster joins)
      DISABLE_CLUSTERING: "true"

  redis:
    command: ["redis-server", "--appendonly", "no", "--save", "", "--requirepass", "${REDIS_PASSWORD}"]
    volumes:
      - /home/melynxis/run/redis:/data
YAML

echo "==> Restarting only Weaviate with .env loaded (so auth/apikeys are honored)"
docker compose \
  --project-directory "$BASE" \
  --env-file "$ENVF" \
  -f "$CORE" -f "$OVR" up -d weaviate

# Quick readiness wait (up to ~30s)
echo "==> Waiting for Weaviate readiness (http 200)…"
for i in {1..30}; do
  if curl -fsS http://127.0.0.1:8080/v1/.well-known/ready >/dev/null; then
    echo "ready"
    exit 0
  fi
  sleep 1
done

echo "not ready; last 80 log lines:"
docker logs --tail=80 solace_weaviate || true
exit 1

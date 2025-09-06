#!/usr/bin/env bash
set -euo pipefail

BASE="http://127.0.0.1:8080"
ENV_DIR="/home/melynxis/solace"
CONTAINER="solace_weaviate"

echo "==> Loading .env from ${ENV_DIR}"
set -a; . "${ENV_DIR}/.env"; set +a || {
  echo "!! Could not source ${ENV_DIR}/.env"; exit 1;
}

echo "==> Host WEAVIATE_APIKEY overview"
if [[ -z "${WEAVIATE_APIKEY:-}" ]]; then
  echo "!! WEAVIATE_APIKEY is empty in your shell. Export it or ensure .env has it."
  exit 1
fi
# Show length and any hidden whitespace
printf "  key length: %d\n" "${#WEAVIATE_APIKEY}"
printf "  key bytes : "; printf '%s' "$WEAVIATE_APIKEY" | hexdump -C | head -n1

echo "==> Container-side env (ensures the container has the same key)"
docker exec -i "$CONTAINER" sh -lc 'env | egrep -i "AUTHENTICATION_APIKEY|ANONYMOUS|PERSISTENCE|CLUSTER|WEAVIATE" | sort' || true

echo "==> Pull out AUTH vars individually"
CON_ALLOWED=$(docker exec -i "$CONTAINER" sh -lc 'printf "%s" "$AUTHENTICATION_APIKEY_ALLOWED_KEYS"')
CON_USERS=$(docker exec -i "$CONTAINER" sh -lc 'printf "%s" "$AUTHENTICATION_APIKEY_USERS"')
CON_ENABLED=$(docker exec -i "$CONTAINER" sh -lc 'printf "%s" "$AUTHENTICATION_APIKEY_ENABLED"')
CON_ANON=$(docker exec -i "$CONTAINER" sh -lc 'printf "%s" "$AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED"')
printf "  ENABLED=%s  ANON=%s  USERS=%s\n" "$CON_ENABLED" "$CON_ANON" "${CON_USERS:-}"
printf "  ALLOWED_KEYS len=%d  bytes: " "${#CON_ALLOWED}"; printf '%s' "$CON_ALLOWED" | hexdump -C | head -n1

echo "==> Compare host key vs container allowed key (raw equality check)"
if [[ "$WEAVIATE_APIKEY" == "$CON_ALLOWED" ]]; then
  echo "  OK: host WEAVIATE_APIKEY matches container AUTHENTICATION_APIKEY_ALLOWED_KEYS"
else
  echo "  MISMATCH!"
  echo "   - host key:      '$WEAVIATE_APIKEY'"
  echo "   - container key: '$CON_ALLOWED'"
  echo "  This will cause 401. Fix .env and restart Weaviate."
fi

echo "==> /ready (no auth expected to be public) …"
curl -sS -o /dev/null -w "  HTTP %{http_code}\n" "$BASE/v1/.well-known/ready" || true

echo "==> /schema with various header forms …"
for H in \
  "-H X-API-KEY:$WEAVIATE_APIKEY" \
  "-H X-API-KEY: $WEAVIATE_APIKEY" \
  "-H Authorization: Bearer $WEAVIATE_APIKEY" \
  ; do
  echo "  trying: curl $H $BASE/v1/schema"
  code=$(curl -s -o /tmp/schema.out -w "%{http_code}" $H "$BASE/v1/schema" || true)
  echo "    -> HTTP $code"
  if [[ "$code" != "200" ]]; then
    echo "    body (truncated):"
    head -c 300 /tmp/schema.out; echo
  fi
done

echo "==> In-container curl (bypass host networking quirks) …"
docker exec -i "$CONTAINER" sh -lc '
  apk add --no-cache curl >/dev/null 2>&1 || true
  echo "  /ready no header:"
  curl -s -o /dev/null -w "    HTTP %{http_code}\n" http://127.0.0.1:8080/v1/.well-known/ready
  echo "  /schema with X-API-KEY:"
  curl -s -o /tmp/s.out -w "    HTTP %{http_code}\n" -H "X-API-KEY: '"$WEAVIATE_APIKEY"'" http://127.0.0.1:8080/v1/schema
  echo "    body (truncated):"
  head -c 300 /tmp/s.out; echo
'

echo "==> If still 401 and keys match exactly:"
cat <<'EOF'
- Check for stray whitespace in .env (no quotes, no trailing spaces):
    WEAVIATE_APIKEY=the_actual_key
- Remove USERS if not needed:
    AUTHENTICATION_APIKEY_USERS=        # or omit
- Restart only Weaviate with env applied:
    docker compose --env-file /home/melynxis/solace/.env -f /home/melynxis/solace/infra/compose.core.yml up -d weaviate
EOF

echo "✅ Done."

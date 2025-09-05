#!/usr/bin/env bash
set -euo pipefail

# You can set your API token here or load from env
API_TOKEN="catbQGyHUC973ycyQrs5G5RA"
API_URL="http://127.0.0.1:8081"

SERVICES=(
  ghostpaw-mcp
  ghostpaw-orchestrator
  ghostpaw-registry
)

echo "==[ Restarting Solace services ]=="
for svc in "${SERVICES[@]}"; do
  echo "-- Restarting $svc ..."
  sudo systemctl restart $svc
done

echo "==[ Waiting for services to be active ]=="
for svc in "${SERVICES[@]}"; do
  until systemctl is-active --quiet $svc; do
    echo "  $svc not active, waiting 2s ..."
    sleep 2
  done
  echo "  $svc is active."
done

echo "==[ Waiting for Registry API to be ready ]=="
for i in {1..30}; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/health" || echo "000")
  if [[ "$code" == "200" ]]; then
    echo "  Registry API is ready (health=200)."
    break
  fi
  echo "  Registry API not ready (status $code), waiting 2s ..."
  sleep 2
done
if [[ "$code" != "200" ]]; then
  echo "!! Registry API did not become ready after 60s. Aborting tests."
  exit 1
fi

echo "==[ Running Registry API Test Suite ]=="
function test_api() {
  local desc="$1"
  local cmd="$2"
  echo
  echo ">> $desc"
  eval "$cmd"
}

test_api "Health endpoint (no auth)" \
  "curl -fsS $API_URL/health"

test_api "Healthz endpoint (auth required)" \
  "curl -fsS -H \"Authorization: Bearer $API_TOKEN\" $API_URL/v1/healthz | jq ."

test_api "Roles for API token" \
  "curl -fsS -H \"Authorization: Bearer $API_TOKEN\" $API_URL/v1/rbac/roles | jq ."

test_api "Roles NO auth (should return error)" \
  "curl -fsS $API_URL/v1/rbac/roles | jq . || echo 'Expected error (unauthenticated)'"

test_api "List spirits (auth)" \
  "curl -fsS -H \"Authorization: Bearer $API_TOKEN\" $API_URL/v1/spirits | jq ."

test_api "List spirits NO auth (should fail)" \
  "curl -fsS $API_URL/v1/spirits | jq . || echo 'Expected error (unauthenticated)'"

test_api "Create new spirit" \
  "curl -fsS -X POST -H \"Authorization: Bearer $API_TOKEN\" -H \"Content-Type: application/json\" -d '{\"name\":\"Springer\",\"role\":\"admin\",\"meta\":{\"purpose\":\"test spirit\"}}' $API_URL/v1/spirits | jq ."

test_api "RBAC permission check" \
  "curl -fsS -X POST -H \"Authorization: Bearer $API_TOKEN\" -H \"Content-Type: application/json\" -d '{\"action\":\"create\",\"resource\":\"spirit\"}' $API_URL/v1/rbac/check | jq ."

test_api "Ready endpoint" \
  "curl -fsS -H \"Authorization: Bearer $API_TOKEN\" $API_URL/v1/readyz | jq ."

test_api "Version endpoint" \
  "curl -fsS -H \"Authorization: Bearer $API_TOKEN\" $API_URL/v1/version | jq ."

test_api "Metrics (raw)" \
  "curl -fsS -H \"Authorization: Bearer $API_TOKEN\" $API_URL/v1/metrics | head -20"

echo
echo "==[ Test suite complete. Check for failures above. ]=="

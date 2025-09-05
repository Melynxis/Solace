# Set your API key (if auth is enabled; for now these endpoints are open)
API_KEY="testkey"
REQUEST_ID=$(uuidgen)

# Health should be plain text "ok"
echo "== Health =="
curl -fsS http://127.0.0.1:8081/health

echo -e "\n\n== Spirits: Create =="
curl -fsS -X POST http://127.0.0.1:8081/spirits \
  -H "Content-Type: application/json" \
  -H "X-Request-Id: $REQUEST_ID" \
  -d '{"name":"TestSpirit","role":"agent","meta":{"foo":"bar"}}' | jq .

echo -e "\n\n== Spirits: List =="
curl -fsS http://127.0.0.1:8081/spirits | jq .

echo -e "\n\n== Spirits: Error case (404) =="
curl -fsS http://127.0.0.1:8081/spirits/999999 | jq .

echo -e "\n\n== RBAC: List roles =="
curl -fsS http://127.0.0.1:8081/v1/rbac/roles | jq .

echo -e "\n\n== RBAC: Permission check =="
curl -fsS -X POST http://127.0.0.1:8081/v1/rbac/check \
  -H "Content-Type: application/json" \
  -d '{"subject":"alice","action":"view","resource":"spirit:1"}' | jq .

echo -e "\n\n== Registry: Create =="
curl -fsS -X POST http://127.0.0.1:8081/registry \
  -H "Content-Type: application/json" \
  -d '{"name":"TestTool","type":"tool","config":{"foo":"bar"},"auth_mode":"none","status":"active"}' | jq .

echo -e "\n\n== Registry: List =="
curl -fsS http://127.0.0.1:8081/registry | jq .

echo -e "\n\n== Registry: Error case (404) =="
curl -fsS http://127.0.0.1:8081/registry/999999 | jq .

echo -e "\n\n== Metrics =="
curl -fsS http://127.0.0.1:8081/metrics | head -20

echo -e "\n\n== Spirits: Patch (should error if no changes) =="
curl -fsS -X PATCH http://127.0.0.1:8081/spirits/1 \
  -H "Content-Type: application/json" \
  -d '{}' | jq .

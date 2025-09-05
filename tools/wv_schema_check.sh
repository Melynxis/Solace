#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-http://127.0.0.1:8080}"
KEY="${WEAVIATE_APIKEY:-}"

echo "==> Testing /ready (public)"
curl -s -o /dev/null -w "ready=%{http_code}\n" "$BASE/v1/.well-known/ready"

if [[ -z "$KEY" ]]; then
  echo "!! WEAVIATE_APIKEY not set in env; Bearer tests will be skipped."
  exit 0
fi

echo "==> Testing /schema with Authorization: Bearer (expected 200)"
curl -s -H "Authorization: Bearer $KEY" "$BASE/v1/schema" | jq .

echo "==> (FYI) Testing /schema with X-API-KEY (often 401 on this build)"
code=$(curl -s -o /dev/null -w "%{http_code}" -H "X-API-KEY: $KEY" "$BASE/v1/schema")
echo "schema(X-API-KEY) http=$code"


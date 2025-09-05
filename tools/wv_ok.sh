#!/usr/bin/env bash
set -euo pipefail
: "${WEAVIATE_APIKEY:?WEAVIATE_APIKEY not set}"

BASE="http://127.0.0.1:8080"

echo "==> /ready"
curl -fsS "$BASE/v1/.well-known/ready" | jq .

echo "==> /schema (Authorization: Bearer)"
curl -fsS -H "Authorization: Bearer $WEAVIATE_APIKEY" \
  "$BASE/v1/schema" | jq .

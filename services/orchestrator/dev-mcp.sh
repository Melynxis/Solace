#!/usr/bin/env bash
set -euo pipefail

BASE="/home/melynxis/solace/services/orchestrator"
cd "$BASE"

if [[ -f "/home/melynxis/solace/.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "/home/melynxis/solace/.env"
  set +a
fi

python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip >/dev/null
pip install -r requirements.txt

exec uvicorn mcp:app --host 0.0.0.0 --port 8083 --reload

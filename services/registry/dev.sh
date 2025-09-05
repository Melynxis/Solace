# /home/melynxis/solace/services/registry/dev.sh
#!/usr/bin/env bash
set -euo pipefail

BASE="/home/melynxis/solace/services/registry"
cd "$BASE"

# Load env from root .env so DB creds are present
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

# Run on 0.0.0.0 so LAN can reach it (UFW will gate)
exec uvicorn app:app --host 0.0.0.0 --port "${REGISTRY_PORT:-8081}" --reload

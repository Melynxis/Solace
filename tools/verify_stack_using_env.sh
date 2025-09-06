#!/usr/bin/env bash
# /home/melynxis/solace/tools/verify_stack_using_env.sh
set -Eeuo pipefail

SOLACE_DIR="/home/melynxis/solace"
cd "$SOLACE_DIR"

echo "==> Loading .env from $SOLACE_DIR"
if [[ ! -f .env ]]; then
  echo "ERROR: .env not found at $SOLACE_DIR"
  exit 1
fi

# Export everything from .env into the current shell
set -a
# shellcheck source=/dev/null
source .env
set +a

# Helper to check a command exists
need() { command -v "$1" >/dev/null 2>&1 || { echo "!! '$1' missing"; return 1; }; }

# Show a few key envs (masked)
mask() { python3 - <<'PY' "$1"
import os,sys
v=os.environ.get(sys.argv[1],"")
print(v if len(v)<=4 else v[:2]+"*"*(max(0,len(v)-4))+v[-2:])
PY
}
echo "Vars: MYSQL_USER='${MYSQL_USER:-}'  MYSQL_PASSWORD='$(mask MYSQL_PASSWORD)'  REDIS_PASSWORD='$(mask REDIS_PASSWORD)'"

# Guardrails for required vars
missing=0
for v in MYSQL_USER MYSQL_PASSWORD; do
  if [[ -z "${!v:-}" ]]; then echo "!! $v is not set"; missing=1; fi
done
if (( missing )); then
  echo "Fix your .env (or ensure this script runs from $SOLACE_DIR) and retry."
  exit 2
fi

echo
echo "==> MySQL check (TCP to 127.0.0.1:3306) ..."
if ! need mysql; then
  echo "   Hint: sudo apt install mysql-client-core-8.0"
else
  set +e
  mysql --protocol=TCP -h 127.0.0.1 -P 3306 -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1
  rc=$?
  set -e
  if (( rc == 0 )); then
    echo "   OK: MySQL auth works for user '$MYSQL_USER'"
  else
    echo "   FAIL: MySQL login for '$MYSQL_USER' failed."
    echo "   Troubleshoot:"
    echo "     - Confirm .env creds"
    echo "     - Ensure the DB has GRANTs for '$MYSQL_USER'@'%'"
    echo "     - Try: mysql --protocol=TCP -h 127.0.0.1 -P 3306 -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -e \"SELECT user,host FROM mysql.user;\""
  fi
fi

echo
echo "==> Redis check ..."
if ! need redis-cli; then
  echo "   Hint: sudo apt install redis-tools"
else
  if [[ -n "${REDIS_PASSWORD:-}" ]]; then
    if redis-cli -a "$REDIS_PASSWORD" PING >/dev/null 2>&1; then
      echo "   OK: Redis AUTH and PING succeeded"
    else
      echo "   FAIL: Redis AUTH/PING failed (check REDIS_PASSWORD and that Redis requires a password)."
    fi
  else
    if redis-cli PING >/dev/null 2>&1; then
      echo "   OK: Redis PING (no auth) succeeded"
    else
      echo "   FAIL: Redis PING failed"
    fi
  fi
fi

echo
echo "==> Weaviate readiness ..."
if need curl; then
  ready=$(curl -fsS http://127.0.0.1:8080/v1/.well-known/ready || true)
  live=$(curl -fsS http://127.0.0.1:8080/v1/.well-known/live  || true)
  [[ -n "$ready" ]] && echo "   /ready: $ready" || echo "   /ready: (no response)"
  [[ -n "$live"  ]] && echo "   /live : $live"  || echo "   /live : (no response)"
else
  echo "   Hint: install curl"
fi

echo
echo "✅ Checks complete."

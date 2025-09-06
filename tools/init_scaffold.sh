# /home/melynxis/solace/tools/init_scaffold.sh  (server: Solace)
#!/usr/bin/env bash
set -euo pipefail
umask 022

BASE="/home/melynxis/solace"

dirs=(
  "$BASE"
  "$BASE/apps"
  "$BASE/apps/ghostpaw-dashboard"
  "$BASE/services"
  "$BASE/services/orchestrator"
  "$BASE/services/registry"
  "$BASE/services/hooks"
  "$BASE/infra"
  "$BASE/infra/exporters"
  "$BASE/spirits"
  "$BASE/tools"
  "$BASE/docs"
  "$BASE/legacy"
  "$BASE/logs"
  "$BASE/tmp"
)

echo "[1/4] Creating directories..."
for d in "${dirs[@]}"; do
  mkdir -p "$d"
done

echo "[2/4] Dropping .gitkeep placeholders..."
# Add .gitkeep to non-root dirs so git tracks empty folders
for d in "${dirs[@]:1}"; do
  touch "$d/.gitkeep"
done

echo "[3/4] Writing minimal README and env skeleton..."
# Root README with key guardrails
cat > "$BASE/README.md" <<'README'
# Solace (single-host)

- **Single host:** All Solace services run on the **Solace** machine.
- **Tmux scope:** Tmux is used **only** for Spirit **Creation** and **Modification** flows. Runtime spirits run as normal services.
- **Observability:** Prometheus/Grafana live on a separate Observability host. Solace exposes metrics; Observability scrapes/pulls.
- **Dirs**
  - `apps/ghostpaw-dashboard` — UI
  - `services/registry` — API for spirit records (+ /metrics)
  - `services/orchestrator` — tmux-based create/modify flows
  - `services/hooks` — stubs (Vigil/Mica/etc.)
  - `infra` — compose files (core + exporters)
  - `spirits` — per-spirit working dirs/specs
  - `docs` — current specs
  - `legacy` — archived refs (code/specs here supersede)
  - `logs`, `tmp` — runtime convenience

> Next steps will populate compose files, API skeletons, and scripts incrementally.
README

# Example env skeleton (adjust later)
cat > "$BASE/.env.example" <<'ENV'
# ==== Solace .env (example) ====
# DB
MYSQL_ROOT_PASSWORD=solace_root_pwd
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
MYSQL_DB=solace
MYSQL_USER=solace_app
MYSQL_PASSWORD=solace_app_pwd

# Redis
REDIS_URL=redis://127.0.0.1:6379

# Registry API
REGISTRY_PORT=8081

# Observability
OBSERVABILITY_HOST=192.0.2.10   # <-- replace with your Prom/Grafana box IP
PUSHGATEWAY_URL=http://192.0.2.10:9091
ENV

# Stub compose files as placeholders (content to be filled in next steps)
cat > "$BASE/infra/compose.core.yml" <<'YML'
# placeholder; will be populated in the next step
# services: mysql, redis, weaviate
YML

cat > "$BASE/infra/exporters.compose.yml" <<'YML'
# placeholder; will be populated in the next step
# exporters: node_exporter, mysqld_exporter, redis_exporter, (optional) blackbox_exporter
YML

echo "[4/4] Setting permissions..."
chmod -R u+rwX,go+rX "$BASE"
chmod -R u+rwX "$BASE/tools" || true

echo
echo "Scaffold complete at: $BASE"
echo "Preview of the tree (if 'tree' exists):"
if command -v tree >/dev/null 2>&1; then
  tree -a -I ".venv|node_modules|__pycache__" "$BASE"
else
  find "$BASE" -maxdepth 3 -type d -print | sed "s|$BASE|.|"
fi

echo
echo "Next: we'll populate compose files and minimal services step-by-step."

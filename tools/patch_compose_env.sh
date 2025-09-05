# /home/melynxis/solace/tools/patch_compose_env.sh
#!/usr/bin/env bash
set -euo pipefail
BASE="/home/melynxis/solace"
ENV_FILE="$BASE/.env"

patch_file () {
  local f="$1"
  [[ -f "$f" ]] || return 0
  cp -a "$f" "${f}.bak.$(date +%s)"

  # Replace plain 'docker compose -f "$FILE" up -d' with env-aware variant
  sed -i \
    -e 's#docker compose -f "\$BASE/infra/compose.core.yml" up -d#docker compose --project-directory "'"$BASE"'" --env-file "'"$ENV_FILE"'" -f "$BASE/infra/compose.core.yml" up -d#g' \
    -e 's#docker compose -f "\$BASE/infra/exporters.compose.yml" up -d#docker compose --project-directory "'"$BASE"'" --env-file "'"$ENV_FILE"'" -f "$BASE/infra/exporters.compose.yml" up -d#g' \
    -e 's#docker compose -f "\$FILE" up -d#docker compose --project-directory "'"$BASE"'" --env-file "'"$ENV_FILE"'" -f "$FILE" up -d#g' \
    -e 's#docker compose -f /home/melynxis/solace/infra/exporters.compose.yml up -d#docker compose --project-directory "'"$BASE"'" --env-file "'"$ENV_FILE"'" -f /home/melynxis/solace/infra/exporters.compose.yml up -d#g' \
    "$f"
}

patch_file "$BASE/tools/infra_up.sh"                || true
patch_file "$BASE/tools/exporters_up.sh"            || true
patch_file "$BASE/tools/fix_exporters_network.sh"   || true
patch_file "$BASE/tools/fix_mysqld_exporter_hostnet.sh" || true
patch_file "$BASE/tools/fix_mysqld_exporter_network_conflict.sh" || true
patch_file "$BASE/tools/fix_mysqld_exporter_cnf.sh" || true
patch_file "$BASE/tools/reconfigure_mysqld_exporter_core_net.sh" || true

echo "✅ Patched docker compose calls to always load $ENV_FILE"

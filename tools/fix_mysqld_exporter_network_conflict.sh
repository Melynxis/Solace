# /home/melynxis/solace/tools/fix_mysqld_exporter_network_conflict.sh
#!/usr/bin/env bash
set -euo pipefail

FILE="/home/melynxis/solace/infra/exporters.compose.yml"
backup="${FILE}.bak.$(date +%s)"
cp -a "$FILE" "$backup"
echo "Backed up to $backup"

python3 - "$FILE" <<'PY'
import re, sys
p=sys.argv[1]
t=open(p).read()

m=re.search(r'(\n  mysqld_exporter:\n(?:.*\n)*?)(?=\n  \w|$)', t)
if not m:
    print("mysqld_exporter block not found", file=sys.stderr); sys.exit(1)
blk=m.group(1)

# Remove any networks:.. block in mysqld_exporter
blk=re.sub(r'\n\s+networks:\n(?:\s+-\s*\w+\n)+', '\n', blk)

# Remove ports: mapping (host networking does not need it)
blk=re.sub(r'\n\s+ports:\n(?:\s+-\s*".*"\n)+', '\n', blk)

# Ensure network_mode: host
if 'network_mode:' not in blk:
    blk = re.sub(r'(\n\s+restart:.*\n)', r'\1    network_mode: host\n', blk)
else:
    blk = re.sub(r'network_mode:\s*\S+', 'network_mode: host', blk)

# Ensure DATA_SOURCE_NAME points to host MySQL
blk=re.sub(
    r'DATA_SOURCE_NAME:\s*".*@"?\(.*?\)\/"',
    'DATA_SOURCE_NAME: "exporter:${MYSQL_EXPORTER_PASSWORD:-exporter_pwd}@(127.0.0.1:3306)/"',
    blk
)

t = t[:m.start(1)] + blk + t[m.end(1):]
open(p,'w').write(t)
PY

echo "Restarting exporters..."
docker compose --project-directory "/home/melynxis/solace" --env-file "/home/melynxis/solace/.env" -f "$FILE" up -d

echo "Waiting 5s, then checking mysqld_exporter on http://127.0.0.1:9104/metrics ..."
sleep 5
curl -fsS http://127.0.0.1:9104/metrics | head -n 10 || {
  echo "mysqld_exporter still not responding."
  echo "Logs:"
  docker logs --tail=200 solace_mysqld_exporter || true
  exit 1
}
echo "✅ mysqld_exporter responding on :9104"

# /home/melynxis/solace/tools/install_mysql_client.sh
#!/usr/bin/env bash
set -euo pipefail
sudo apt-get update -y
sudo apt-get install -y mysql-client-core-8.0
echo "✅ mysql client installed. Try: mysql --version"

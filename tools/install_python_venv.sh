# /home/melynxis/solace/tools/install_python_venv.sh
#!/usr/bin/env bash
set -euo pipefail
sudo apt-get update -y
# Ubuntu 24.04 uses Python 3.12
sudo apt-get install -y python3.12-venv python3-pip
python3 --version
pip3 --version || true
echo "✅ python venv + pip installed."

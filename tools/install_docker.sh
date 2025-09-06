# /home/melynxis/solace/tools/install_docker.sh
#!/usr/bin/env bash
set -euo pipefail

# Detect architecture and OS family (assumes Ubuntu/Debian)
if ! command -v apt >/dev/null 2>&1; then
  echo "This installer currently supports apt-based systems. If you're on another distro, tell me and I'll adjust."
  exit 1
fi

echo "[1/6] Removing old Docker bits (if any)..."
sudo apt-get remove -y docker docker-engine docker.io containerd runc || true

echo "[2/6] Installing prerequisites..."
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release

echo "[3/6] Adding Docker’s official GPG key & repo..."
sudo install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
fi
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "[4/6] Installing Docker Engine + Compose plugin..."
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[5/6] Enabling and starting Docker..."
sudo systemctl enable docker
sudo systemctl start docker

echo "[6/6] Adding current user to 'docker' group..."
sudo usermod -aG docker "$USER"

echo
echo "Verifying Docker installation..."
docker --version || { echo "Docker CLI not available for current shell yet."; }
docker compose version || echo "Compose plugin will work after group refresh."

echo
echo "Applying group change in this shell (no full logout needed)..."
newgrp docker <<'EOF'
echo
echo "Testing 'docker run hello-world' (this pulls a small image)..."
docker run --rm hello-world || true
EOF

echo
echo "✅ Docker install completed."
echo "If any command above complained about permissions, open a NEW terminal/session and try 'docker ps' again."

#!/usr/bin/env bash
set -Eeuo pipefail

echo "========================================"
echo " SIDOAK DOCKER SETUP"
echo "========================================"

if [ "$EUID" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

APP_DIR="/opt/sidoak"

echo "[1/8] Remove old Docker packages..."

apt remove -y docker docker-engine docker.io containerd runc || true

echo "[2/8] Add Docker GPG key..."

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
| gpg --dearmor -o /etc/apt/keyrings/docker.gpg

chmod a+r /etc/apt/keyrings/docker.gpg

echo "[3/8] Add Docker repository..."

echo \
"deb [arch=$(dpkg --print-architecture) \
signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
| tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "[4/8] Install Docker..."

apt update -y

apt install -y \
docker-ce \
docker-ce-cli \
containerd.io \
docker-buildx-plugin \
docker-compose-plugin

echo "[5/8] Enable Docker..."

systemctl enable docker
systemctl start docker

echo "[6/8] Docker optimization..."

mkdir -p /etc/docker

cat <<EOF >/etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true
}
EOF

systemctl restart docker

echo "[7/8] Create project structure..."

mkdir -p ${APP_DIR}/docker
mkdir -p ${APP_DIR}/mail
mkdir -p ${APP_DIR}/nginx
mkdir -p ${APP_DIR}/postgres
mkdir -p ${APP_DIR}/redis
mkdir -p ${APP_DIR}/app
mkdir -p ${APP_DIR}/logs
mkdir -p ${APP_DIR}/backups
mkdir -p ${APP_DIR}/scripts

touch ${APP_DIR}/.env

echo "[8/8] Docker test..."

docker run hello-world

echo ""
docker --version
docker compose version

echo ""
echo "========================================"
echo " DOCKER SETUP COMPLETE"
echo "========================================"
echo ""
echo "Next:"
echo "sudo ./03-mail-stack.sh"
echo ""

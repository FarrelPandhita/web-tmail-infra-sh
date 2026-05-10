#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================================
# SIDOAK VPS BOOTSTRAP
# Ubuntu 24.04 LTS
# Optimized for 2vCPU / 2GB RAM
# ==========================================================

DOMAIN="sidoak.my.id"
HOSTNAME_FQDN="mail.sidoak.my.id"
TIMEZONE="Asia/Jakarta"
APP_DIR="/opt/sidoak"

echo "========================================"
echo " SIDOAK VPS BOOTSTRAP"
echo "========================================"

# --- Root Check ---
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# --- Validate Ubuntu ---
if ! grep -q "Ubuntu 24.04" /etc/os-release; then
  echo "Ubuntu 24.04 required"
  exit 1
fi

echo "[1/12] Updating system..."
apt update -y
apt upgrade -y

echo "[2/12] Setting timezone..."
timedatectl set-timezone ${TIMEZONE}

echo "[3/12] Setting hostname..."
hostnamectl set-hostname ${HOSTNAME_FQDN}

if ! grep -q "${HOSTNAME_FQDN}" /etc/hosts; then
  echo "127.0.1.1 ${HOSTNAME_FQDN} mail" >> /etc/hosts
fi

echo "[4/12] Installing base packages..."
apt install -y \
curl \
wget \
git \
nano \
vim \
zip \
unzip \
htop \
jq \
ufw \
fail2ban \
ca-certificates \
gnupg \
lsb-release \
software-properties-common \
apt-transport-https \
dnsutils \
net-tools \
cron \
logrotate

echo "[5/12] Configuring swap (2GB)..."

if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
fi

if ! grep -q "/swapfile" /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "[6/12] Optimizing swap..."
cat <<EOF >/etc/sysctl.d/99-sidoak.conf
vm.swappiness=10
vm.vfs_cache_pressure=50
net.core.somaxconn=1024
fs.file-max=2097152
EOF

sysctl --system

echo "[7/12] Creating project directories..."

mkdir -p ${APP_DIR}/{infra,docker,mail,nginx,app,postgres,redis,logs,backups,scripts}

chmod -R 755 ${APP_DIR}

echo "[8/12] Setting log rotation..."
cat <<EOF >/etc/logrotate.d/sidoak
${APP_DIR}/logs/*.log {
    daily
    rotate 14
    compress
    missingok
    notifempty
    copytruncate
}
EOF

echo "[9/12] Enable services..."
systemctl enable cron
systemctl enable fail2ban

echo "[10/12] DNS sanity check..."
echo "Checking mail.${DOMAIN}"

dig +short mail.${DOMAIN} || true

echo "[11/12] Memory status..."
free -h

echo "[12/12] Final hostname check..."
hostname -f

echo ""
echo "========================================"
echo " BOOTSTRAP COMPLETED"
echo "========================================"
echo ""
echo "Next:"
echo "sudo ./01-security.sh"
echo ""

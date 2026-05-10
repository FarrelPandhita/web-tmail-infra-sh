#!/usr/bin/env bash
set -Eeuo pipefail

echo "========================================"
echo " SIDOAK SECURITY HARDENING"
echo "========================================"

if [ "$EUID" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

echo "[1/8] Configure UFW..."

ufw default deny incoming
ufw default allow outgoing

# SSH
ufw allow 22/tcp

# HTTP / HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# Mail ports
ufw allow 25/tcp
ufw allow 465/tcp
ufw allow 587/tcp
ufw allow 993/tcp

ufw --force enable

echo "[2/8] Configure Fail2Ban..."

mkdir -p /etc/fail2ban

cat <<EOF >/etc/fail2ban/jail.local
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd
destemail = admin@sidoak.my.id
sender = fail2ban@sidoak.my.id

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s

[postfix]
enabled = true

[dovecot]
enabled = true

[nginx-http-auth]
enabled = true
EOF

systemctl restart fail2ban
systemctl enable fail2ban

echo "[3/8] SSH hardening..."

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config

sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/g' /etc/ssh/sshd_config

grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config || \
echo "PasswordAuthentication no" >> /etc/ssh/sshd_config

grep -q "^PubkeyAuthentication yes" /etc/ssh/sshd_config || \
echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config

echo "[4/8] Restart SSH..."
systemctl restart ssh

echo "[5/8] Kernel security tuning..."

cat <<EOF >/etc/sysctl.d/99-security.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
EOF

sysctl --system

echo "[6/8] Disable unused services..."
systemctl disable apport || true

echo "[7/8] UFW status..."
ufw status verbose

echo "[8/8] Fail2Ban status..."
fail2ban-client status

echo ""
echo "========================================"
echo " SECURITY HARDENING DONE"
echo "========================================"
echo ""
echo "Next:"
echo "sudo ./02-docker.sh"
echo ""

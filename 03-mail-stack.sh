#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="sidoak.my.id"
HOSTNAME="mail.sidoak.my.id"

echo "========================================"
echo " SIDOAK MAIL STACK V2"
echo "========================================"

if [ "$EUID" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

echo "[1/9] Install packages..."

apt update -y

DEBIAN_FRONTEND=noninteractive apt install -y \
postfix \
postfix-pcre \
mailutils \
rsyslog \
certbot

echo "[2/9] Backup config..."

mkdir -p /root/postfix-backup
cp -r /etc/postfix/* /root/postfix-backup/ || true

echo "[3/9] Configure hostname..."

postconf -e "myhostname = ${HOSTNAME}"
postconf -e "mydomain = ${DOMAIN}"
postconf -e "myorigin = \$mydomain"

echo "[4/9] Configure interfaces..."

postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"

echo "[5/9] Configure destination..."

postconf -e "mydestination = localhost"
postconf -e "virtual_alias_domains = ${DOMAIN}"
postconf -e "virtual_alias_maps = regexp:/etc/postfix/virtual_regexp"

cat <<EOF >/etc/postfix/virtual_regexp
/.*/ otpcatch
EOF

postmap /etc/postfix/virtual_regexp || true

echo "[6/9] Configure catch-all..."

echo "otpcatch:x:2000:2000:OTP Catch:/home/otpcatch:/usr/sbin/nologin" >> /etc/passwd || true

mkdir -p /home/otpcatch/mail
mkdir -p /var/mail/otp

chown -R root:root /var/mail/otp

cat <<EOF >/etc/aliases
postmaster: root
root: root
EOF

newaliases

echo "[7/9] Configure transport..."

postconf -e "mailbox_transport = local"
postconf -e "local_recipient_maps ="

echo "[8/9] Restart services..."

systemctl enable postfix
systemctl restart postfix
systemctl restart rsyslog

echo "[9/9] Status check..."

systemctl status postfix --no-pager | head -20

echo ""
echo "========================================"
echo " MAIL STACK INSTALLED"
echo "========================================"

echo ""
echo "Test:"
echo "echo test | mail -s hello root@${DOMAIN}"
echo ""
echo "Next:"
echo "sudo ./04-database.sh"
echo ""

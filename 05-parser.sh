#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="/opt/sidoak"

echo "========================================"
echo " SIDOAK OTP PARSER"
echo "========================================"

if [ "$EUID" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

echo "[1/8] Install dependencies..."

apt update -y

apt install -y \
python3 \
python3-pip \
python3-venv \
python3-psycopg2 \
python3-watchdog

echo "[2/8] Create parser directories..."

mkdir -p ${APP_DIR}/parser
mkdir -p ${APP_DIR}/logs

echo "[3/8] Create Python venv..."

python3 -m venv ${APP_DIR}/venv

source ${APP_DIR}/venv/bin/activate

pip install --upgrade pip
pip install psycopg2-binary watchdog python-dotenv

echo "[4/8] Load DB credentials..."

source /opt/sidoak/infra/db.env

cat <<EOF > ${APP_DIR}/parser/.env
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
DB_HOST=localhost
MAILDIR=/home/otpcatch/Maildir/new
EOF

echo "[5/8] Create parser service..."

cat <<EOF >/etc/systemd/system/sidoak-parser.service
[Unit]
Description=SIDOAK OTP Mail Parser
After=network.target postgresql.service postfix.service

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}/parser
ExecStart=${APP_DIR}/venv/bin/python parser.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "[6/8] Create retention cron..."

cat <<EOF >/etc/cron.daily/sidoak-cleanup
#!/bin/bash
sudo -u postgres psql sidoak_mail -c "
DELETE FROM inbox_messages
WHERE received_at < NOW() - INTERVAL '10 days';
"
EOF

chmod +x /etc/cron.daily/sidoak-cleanup

echo "[7/8] Reload systemd..."

systemctl daemon-reload

echo "[8/8] Done."

echo ""
echo "========================================"
echo " PARSER FOUNDATION READY"
echo "========================================"

echo ""
echo "Next:"
echo "nano /opt/sidoak/parser/parser.py"
echo ""

#!/usr/bin/env bash
set -Eeuo pipefail

DB_NAME="sidoak_mail"
DB_USER="sidoak_admin"
DB_PASS=$(openssl rand -base64 32)

echo "========================================"
echo " SIDOAK DATABASE SETUP"
echo "========================================"

if [ "$EUID" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

echo "[1/7] Install PostgreSQL..."

apt update -y
apt install -y \
postgresql \
postgresql-contrib

systemctl enable postgresql
systemctl start postgresql

echo "[2/7] Create database..."

sudo -u postgres psql <<EOF
CREATE USER ${DB_USER} WITH ENCRYPTED PASSWORD '${DB_PASS}';
CREATE DATABASE ${DB_NAME};
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
EOF

echo "[3/7] Create schema..."

sudo -u postgres psql ${DB_NAME} <<EOF

CREATE TABLE admins (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role VARCHAR(50) DEFAULT 'generator_admin',
    is_superadmin BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE buyers (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE generated_emails (
    id SERIAL PRIMARY KEY,
    buyer_id INTEGER REFERENCES buyers(id),
    generated_email VARCHAR(255) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_by INTEGER REFERENCES admins(id),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE inbox_messages (
    id BIGSERIAL PRIMARY KEY,
    generated_email_id INTEGER REFERENCES generated_emails(id),
    sender TEXT,
    recipient TEXT,
    subject TEXT,
    raw_body TEXT,
    otp_code VARCHAR(12),
    received_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE otp_cache (
    id SERIAL PRIMARY KEY,
    generated_email_id INTEGER REFERENCES generated_emails(id),
    latest_otp VARCHAR(12),
    source TEXT,
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    admin_id INTEGER REFERENCES admins(id),
    action TEXT,
    target_email TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_generated_email
ON generated_emails(generated_email);

CREATE INDEX idx_inbox_received
ON inbox_messages(received_at);

CREATE INDEX idx_otp_lookup
ON otp_cache(generated_email_id);

EOF

echo "[4/7] PostgreSQL optimization (2GB RAM)..."

cat <<EOF >> /etc/postgresql/*/main/postgresql.conf

shared_buffers = 256MB
work_mem = 8MB
maintenance_work_mem = 64MB
effective_cache_size = 512MB
max_connections = 100
EOF

systemctl restart postgresql

echo "[5/7] Save credentials..."

mkdir -p /opt/sidoak/infra

cat <<EOF > /opt/sidoak/infra/db.env
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
EOF

chmod 600 /opt/sidoak/infra/db.env

echo "[6/7] Verify tables..."

sudo -u postgres psql ${DB_NAME} -c "\dt"

echo "[7/7] Done."

echo ""
echo "========================================"
echo " DATABASE READY"
echo "========================================"

echo ""
echo "DB credentials:"
cat /opt/sidoak/infra/db.env
echo ""
echo "Next:"
echo "sudo ./05-parser.sh"
echo ""

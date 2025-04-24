#!/usr/bin/env bash

# Zabbix + PostgreSQL Setup Script
# Author: 5.H.4.D.0.W

# ZABBIX_DB_PASS="123456"

# # Color definitions
# RED="\033[0;31m"
# GREEN="\033[0;32m"
# RESET="\033[0m"

# log()    { echo -e "${GREEN}[INFO]${RESET} $1"; }
# err()    { echo -e "${RED}[ERROR]${RESET} $1" >&2; exit 1; }

log "Starting Zabbix server installation..."

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
  err "This script must be run as root."
fi

# Check if OS is Fedora 41
if [ ! -f /etc/redhat-release ]; then
  err "This script is intended for Fedora only"
fi

# Check Fedora version
if grep -ioqvE 'fedora.*41' /etc/redhat-release; then
  err "Fedora version is not supported"
fi

# Add repositories if not already present
REPO_FILE="/etc/yum.repos.d/dsnm.repo"
log "Setting up repositories..."
if [ ! -f "$REPO_FILE" ]; then
  cat > "$REPO_FILE" <<EOF
[Postgresql-17]
name=Postgresql 17 - \$basearch
baseurl=https://download.postgresql.org/pub/repos/yum/17/fedora/fedora-41-\$basearch/
enabled=1
gpgcheck=0
priority=1

[zabbix]
name=Zabbix Official Repository - \$basearch
baseurl=https://repo.zabbix.com/zabbix/7.2/stable/centos/9/\$basearch/
enabled=1
gpgcheck=0
priority=1

[zabbix-sources]
name=Zabbix Official Repository (sources) - \$basearch
baseurl=https://repo.zabbix.com/zabbix/7.2/stable/centos/9/SRPMS/
enabled=1
gpgcheck=0
priority=1

[zabbix-tools]
name=Zabbix Official Repository (tools) - \$basearch
baseurl=https://repo.zabbix.com/zabbix-tools/rhel/9/\$basearch/
enabled=1
gpgcheck=0
priority=1

[zabbix-third-party]
name=Zabbix Official Repository (third-party) - \$basearch
baseurl=https://repo.zabbix.com/third-party/2024-10/centos/9/\$basearch/
enabled=1
gpgcheck=0
priority=1
EOF
else
  log "Repository file already exists: $REPO_FILE"
fi

# Install PostgreSQL
log "Installing PostgreSQL..."
dnf install -y postgresql17 postgresql17-server postgresql17-contrib || err "Failed to install PostgreSQL."

log "Initializing PostgreSQL database..."
postgresql-17-setup initdb || err "Failed to initialize PostgreSQL."

log "Enabling and starting PostgreSQL..."
systemctl enable --now postgresql-17 || err "Failed to start PostgreSQL."

# Install Zabbix
log "Installing Zabbix components..."
dnf install -y zabbix-server-pgsql zabbix-web-pgsql zabbix-apache-conf zabbix-sql-scripts zabbix-selinux-policy zabbix-agent httpd php-fpm || err "Failed to install Zabbix."

# Create Zabbix DB & user
log "Creating Zabbix PostgreSQL user and database..."
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='zabbix'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE ROLE zabbix WITH LOGIN PASSWORD '$ZABBIX_DB_PASS';"

sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw zabbix || \
  sudo -u postgres createdb -O zabbix -E Unicode zabbix

log "Importing Zabbix schema..."
zcat /usr/share/zabbix/sql-scripts/postgresql/server.sql.gz | sudo -u zabbix psql zabbix || err "Failed to import Zabbix schema."

# Update Zabbix server config
CONF_FILE="/etc/zabbix/zabbix_server.conf"
if ! grep -q "^DBPassword=$ZABBIX_DB_PASS" "$CONF_FILE"; then
  log "Updating Zabbix server password config..."
  sed -i "/^# DBPassword=/a DBPassword=$ZABBIX_DB_PASS" "$CONF_FILE"
else
  log "Zabbix server DB password already configured."
fi

# Enable Zabbix and web services
log "Enabling and starting Zabbix and web services..."
systemctl enable --now zabbix-server zabbix-agent httpd php-fpm || err "Failed to enable services."

# Configure firewall for HTTP/HTTPS
log "Configuring firewall to allow HTTP/HTTPS..."
firewall-cmd --zone=public --add-service={http,https} --permanent || err "Failed to add HTTP/HTTPS to firewall."
firewall-cmd --reload || err "Failed to reload firewall rules."

log "Zabbix setup complete."

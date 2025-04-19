#!/usr/bin/env bash

# DSNM Client Setup Script
# Author: 5.H.4.D.0.W

REPO_FILE="/etc/yum.repos.d/dsnm.repo"
REALM="MINIONS.DSNM.SLIIT"
ADMIN_USER="Administrator"
ADMIN_PASS="Admin@123"
ZABBIX_SERVER="192.168.69.1"

# Color definitions
RED="\033[0;31m"
GREEN="\033[0;32m"
RESET="\033[0m"

log()    { echo -e "${GREEN}[INFO]${RESET} $1"; }
err()    { echo -e "${RED}[ERROR]${RESET} $1" >&2; exit 1; }

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
  err "This script must be run as root."
fi

# Disable SELinux (temporary + permanent)
log "Disabling SELinux..."
setenforce 0 || err "Failed to disable SELinux temporarily."
sed -i "/SELINUX=/ s/\(SELINUX=\).*/\1disabled/" /etc/selinux/config || err "Failed to update SELinux config."

# Add Zabbix repository if not present
log "Setting up repositories..."
if [ ! -f "$REPO_FILE" ]; then
  cat > "$REPO_FILE" <<EOF
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
  log "Repository already exists: $REPO_FILE"
fi

# Install required packages
log "Installing DSNM client dependencies..."
dnf install -y realmd sssd adcli krb5-workstation oddjob oddjob-mkhomedir samba samba-common-tools samba-winbind samba-winbind-clients || err "Package installation failed."

# Enable necessary services
log "Enabling required services..."
systemctl enable --now sssd oddjobd || err "Failed to enable services."

# Update crypto policies for AD support
log "Updating crypto policies..."
update-crypto-policies --set DEFAULT:AD-SUPPORT || err "Failed to update crypto policies."

# Backup existing smb.conf
if [ -f /etc/samba/smb.conf ]; then
  BACKUP_FILE="/etc/samba/smb.conf.bak"
  if [ ! -f "$BACKUP_FILE" ]; then
    log "Backing up existing smb.conf..."
    mv /etc/samba/smb.conf "$BACKUP_FILE" || err "Failed to back up smb.conf."
  else
    log "Backup already exists: $BACKUP_FILE"
  fi
fi

# Check if already joined to the domain
if realm list | grep -q "^realm-name: $REALM"; then
  log "Already joined to realm: $REALM"
else
  log "Joining realm: $REALM"
  echo "$ADMIN_PASS" | realm join -U "$ADMIN_USER" "$REALM" --membership-software=samba --client-software=winbind -v || err "Failed to join realm."
fi

# Install and configure Zabbix agent
log "Installing and configuring Zabbix agent..."
dnf install -y zabbix-agent || err "Failed to install Zabbix agent."

log "Opening Zabbix port in firewall..."
firewall-cmd --zone=public --add-port=10050/tcp --permanent || err "Failed to open port."
firewall-cmd --reload || err "Failed to reload firewall."

ZBX_CONF="/etc/zabbix/zabbix_agentd.conf"
hostname_fqdn=$(hostname -f)
sed -i "s|^Hostname=.*|Hostname=$hostname_fqdn|" "$ZBX_CONF"
sed -i "s|^ServerActive=.*|ServerActive=$ZABBIX_SERVER|" "$ZBX_CONF"
sed -i "s|^Server=.*|Server=$ZABBIX_SERVER|" "$ZBX_CONF"

log "Starting and enabling Zabbix agent..."
systemctl enable --now zabbix-agent || err "Failed to enable/start Zabbix agent."

log "DSNM client setup completed."

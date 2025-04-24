#!/usr/bin/env bash

# Samba AD DC Server Setup Script
# Author: 5.H.4.D.0.W

# # Variables
# SAMBA_DOMAIN="minions"
# SAMBA_REALM="${SAMBA_DOMAIN}.dsnm.sliit"
# SAMBA_ADMIN_PASS="Admin@123"
# SAMBA_CLIENT_USER_NAME="student"
# SAMBA_CLIENT_USER_PASS="Pass@123"
# SAMBA_CLIENT_GROUP_NAME="students"

# # Color definitions
# RED="\033[0;31m"
# GREEN="\033[0;32m"
# RESET="\033[0m"

# log()    { echo -e "${GREEN}[INFO]${RESET} $1"; }
# err()    { echo -e "${RED}[ERROR]${RESET} $1" >&2; exit 1; }

log "Staring Samba installation..."

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

# Disable SELinux (temporary + permanent)
log "Disabling SELinux..."
setenforce 0 || err "Failed to disable SELinux temporarily."
sed -i "/SELINUX=/ s/\(SELINUX=\).*/\1disabled/" /etc/selinux/config || err "Failed to update SELinux config."

# Install required packages
log "Installing Samba AD DC server and dependencies..."
dnf install -y samba samba-dc samba-winbind samba-winbind-clients samba-dc-bind-dlz krb5-workstation || err "Failed to install packages."

# Backup existing smb.conf
if [ -f /etc/samba/smb.conf ]; then
  log "Backing up existing smb.conf..."
  mv /etc/samba/smb.conf /etc/samba/smb.conf.bak || err "Failed to backup smb.conf."
fi

# Provision domain
log "Provisioning Samba AD domain..."
samba-tool domain provision \
  --use-rfc2307 \
  --domain="$SAMBA_DOMAIN" \
  --realm="$SAMBA_REALM" \
  --server-role=dc \
  --dns-backend=BIND9_DLZ \
  --adminpass="$SAMBA_ADMIN_PASS" || err "Domain provisioning failed."

# Update Kerberos config
log "Updating Kerberos configuration..."
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf || err "Failed to copy krb5.conf."

# Enable and start Samba service
log "Enabling and starting Samba service..."
systemctl enable --now samba || err "Failed to enable/start Samba."

# Update named.conf if not already configured
log "Configuring BIND DNS integration..."
if ! grep -q 'tkey-gssapi-keytab' /etc/named.conf; then
  sed -i "/options {/a \\\ttkey-gssapi-keytab \"/var/lib/samba/bind-dns/dns.keytab\";\n\tminimal-responses yes;" /etc/named.conf || err "Failed to update named.conf."
else
  log "BIND options already configured."
fi

if ! grep -q 'include "/var/lib/samba/bind-dns/named.conf"' /etc/named.conf; then
  echo "include \"/var/lib/samba/bind-dns/named.conf\";" >> /etc/named.conf || err "Failed to append Samba include to named.conf."
else
  log "Named include already present."
fi

# Add AD functional level to smb.conf if not present
if ! grep -q "ad dc functional level" /etc/samba/smb.conf; then
  sed -i "/\[global\]/a \\\tad dc functional level = 2016" /etc/samba/smb.conf || err "Failed to update smb.conf."
else
  log "Functional level already set in smb.conf."
fi

# Raise domain and forest levels
log "Preparing and raising domain/forest functional levels..."
samba-tool domain functionalprep --function-level=2016 || err "Functional prep failed."
samba-tool domain level raise --domain-level=2016 --forest-level=2016 || err "Failed to raise domain/forest levels."

# Restart services
log "Restarting Samba and named services..."
systemctl restart samba || err "Failed to restart Samba."
systemctl restart named || err "Failed to restart named."

# Create user and group
log "Creating AD user and group..."
samba-tool user show "$SAMBA_CLIENT_USER_NAME" >/dev/null 2>&1 || samba-tool user add "$SAMBA_CLIENT_USER_NAME" "$SAMBA_CLIENT_USER_PASS" || err "Failed to add user."
samba-tool group show "$SAMBA_CLIENT_GROUP_NAME" >/dev/null 2>&1 || samba-tool group add "$SAMBA_CLIENT_GROUP_NAME" || err "Failed to add group."

if ! samba-tool group listmembers "$SAMBA_CLIENT_GROUP_NAME" | grep -q "^$SAMBA_CLIENT_USER_NAME$"; then
  samba-tool group addmembers "$SAMBA_CLIENT_GROUP_NAME" "$SAMBA_CLIENT_USER_NAME" || err "Failed to add user to group."
else
  log "User already in group."
fi

# Configure firewall
log "Configuring firewall..."
firewall-cmd --zone=public --add-service={dns,kerberos,kpasswd,ldap,ldaps,samba} --permanent || err "Failed to add services to firewall."
firewall-cmd --zone=public --add-port={135/tcp,137-138/udp,139/tcp,389/udp,3268-3269/tcp,10051/tcp,49152-65535/tcp} --permanent || err "Failed to open ports."
firewall-cmd --reload || err "Failed to reload firewall."

log "Samba AD Domain Controller setup completed successfully!"

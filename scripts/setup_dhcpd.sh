#!/usr/bin/env bash

# DHCP Server Setup Script
# Author: 5.H.4.D.0.W

# # Variables
# DHCP_INTERFACE="enp1s0"  # Interface to listen on
# DHCP_SUBNET_ADDR="192.168.69.0"  # Subnet address
# DHCP_SUBNET_MASK="255.255.255.0" # Subnet mask
# DHCP_ROUTER="192.168.69.1"  # Router address
# DHCP_BROADCAST_ADDR="192.168.69.255" # Broadcast address
# DHCP_ADDR_RANGE="$DHCP_ROUTER $DHCP_BROADCAST_ADDR" # Range of address in dhcp pool
# DOMAIN_NAME="dsnm.sliit" # Domain name
# DOMAIN_NAME_SERVER="$DHCP_ROUTER" # Domain name server

# # Color definitions
# RED="\033[0;31m"
# GREEN="\033[0;32m"
# RESET="\033[0m"

# log()    { echo -e "${GREEN}[INFO]${RESET} $1"; }
# err()    { echo -e "${RED}[ERROR]${RESET} $1" >&2; exit 1; }

log "Staring DHCP server installation..."

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

# Install DHCP server package
log "Installing DHCP server package..."
dnf install -y dhcp-server || err "Failed to install dhcp-server package."

# Backup existing DHCP configuration
if [ -f /etc/dhcp/dhcpd.conf ]; then
  log "Backing up existing /etc/dhcp/dhcpd.conf..."
  cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak || err "Failed to backup dhcpd.conf."
fi

# Configure DHCP server
log "Configuring DHCP server..."
cat > /etc/dhcp/dhcpd.conf <<EOF
authoritative;

log-facility local7;

subnet $DHCP_SUBNET_ADDR netmask $DHCP_SUBNET_MASK {
  interface $DHCP_INTERFACE;
  range $DHCP_ADDR_RANGE;
  option domain-name-servers ${DOMAIN_NAME_SERVER};
  option domain-name "$DOMAIN_NAME";
  option routers $DHCP_ROUTER;
  option broadcast-address $DHCP_BROADCAST_ADDR;
  default-lease-time 600;
  max-lease-time 7200;
}
EOF

# Configure firewall for DHCP
log "Configuring firewall for DHCP..."
firewall-cmd --zone=public --add-service=dhcp --permanent || err "Failed to add DHCP service to firewall."
firewall-cmd --reload || err "Failed to reload firewall."

# Start and enable DHCP server
log "Starting and enabling DHCP server..."
systemctl start dhcpd || err "Failed to start dhcpd."
systemctl enable dhcpd || err "Failed to enable dhcpd."

log "DHCP server setup complete."

#!/usr/bin/env bash

# DSNM Server Setup Script
# Author: 5.H.4.D.0.W

# Server variables
DHCP_INTERFACE="enp1s0"  # Interface to listen on
DHCP_SUBNET_ADDR="192.168.69.0"  # Subnet address
DHCP_SUBNET_MASK="255.255.255.0" # Subnet mask
DHCP_ROUTER="192.168.69.1"  # Router address
DHCP_BROADCAST_ADDR="192.168.69.255" # Broadcast address
DHCP_ADDR_RANGE="$DHCP_ROUTER $DHCP_BROADCAST_ADDR" # Range of address in dhcp pool

DOMAIN_NAME="dsnm.sliit" # Domain name
DOMAIN_NAME_SERVER="$DHCP_ROUTER" # Domain name server

DNS_SUB_DOMAIN="ns1" # DNS server subdomain
DNS_FORWARD_ZONE="$DOMAIN_NAME" # Forward zone
DNS_REVERSE_ZONE="69.168.192.in-addr.arpa" # Reverse zone
DNS_FORWARDERS="8.8.8.8; 8.8.4.4;" # DNS forwarders
DNS_SERVER_ADDR="192.168.69.1;" # DNS server address
DNS_SERVER_HOST_ID="1" # DNS server host id x.x.x.1
DNS_ALLOW_QUERY="192.168.69.0/24;" # Allow DNS query from

SAMBA_DOMAIN="minions" # Samba subdomain
SAMBA_REALM="${SAMBA_DOMAIN}.${DOMAIN_NAME}" # Realm name
SAMBA_ADMIN_PASS="Admin@123" # Samba administrator password
SAMBA_CLIENT_USER_NAME="student" # Samba example username
SAMBA_CLIENT_USER_PASS="Pass@123" # Samba example user password
SAMBA_CLIENT_GROUP_NAME="students" # Samba example user group

ZABBIX_DB_PASS="123456" # Zabbix postgresql password

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

# Check if OS is Fedora 41
if [ ! -f /etc/redhat-release ]; then
  err "This script is intended for Fedora only"
fi

# Check Fedora version
if grep -ioqvE 'fedora.*41' /etc/redhat-release; then
  err "Fedora version is not supported"
fi

# Run DHCPd installation
source ./scripts/setup_dhcpd.sh

# Run named installation
source ./scripts/setup_named.sh

# Run samba installation
source ./scripts/setup_samba.sh

# Run Zabbix installation
source ./scripts/setup_zabbix.sh

log "DSNM server setup completed."
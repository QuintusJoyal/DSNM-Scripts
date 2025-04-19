#!/usr/bin/env bash

# BIND DNS Server Setup Script
# Author: 5.H.4.D.0.W

# Variables
DOMAIN_NAME="dsnm.sliit"
DNS_SUB_DOMAIN="ns1"
FORWARD_ZONE="$DOMAIN_NAME"
REVERSE_ZONE="69.168.192.in-addr.arpa"
FORWARDERS="8.8.8.8; 8.8.4.4;"
SERVER_ADDR="192.168.69.1;"
SERVER_HOST_ID="1"
MAIL_SERVER_ADDR="$SERVER_ADDR"
ALLOW_QUERY="192.168.69.0/24;"

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

# Install BIND DNS server package
log "Installing BIND DNS server packages..."
dnf install -y bind bind-utils || err "Failed to install BIND packages."

# Backup existing config
if [ -f /etc/named.conf ]; then
  log "Backing up existing /etc/named.conf..."
  cp /etc/named.conf /etc/named.conf.bak || err "Failed to backup named.conf."
fi

# Create named.conf
log "Configuring /etc/named.conf..."
cat > /etc/named.conf <<EOF
options {
        listen-on port 53 { $SERVER_ADDR };

        directory       "/var/named";
        dump-file       "/var/named/data/cache_dump.db";
        statistics-file "/var/named/data/named_stats.txt";
        memstatistics-file "/var/named/data/named_mem_stats.txt";
        recursing-file  "/var/named/data/named.recursing";
        secroots-file   "/var/named/data/named.secroots";
        allow-query     { $ALLOW_QUERY };

        recursion yes;
        forwarders { $FORWARDERS };
        forward only;

        dnssec-validation yes;

        bindkeys-file "/etc/named.root.key";
        managed-keys-directory "/var/named/dynamic";

        pid-file "/run/named/named.pid";
        session-keyfile "/run/named/session.key";
};

logging {
        channel default_debug {
                file "data/named.run";
                severity dynamic;
        };
};

zone "$FORWARD_ZONE" {
        type master;
        file "$DOMAIN_NAME.zone";
        allow-query { $ALLOW_QUERY };
        notify yes;
};

zone "$REVERSE_ZONE" IN {
        type master;
        file "$DOMAIN_NAME.rzone";
        allow-query { $ALLOW_QUERY };
        notify yes;
};

zone "." IN {
        type hint;
        file "named.ca";
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
EOF

# Create forward zone file
FORWARD_FILE="/var/named/${DOMAIN_NAME}.zone"
if [ ! -f "$FORWARD_FILE" ]; then
  log "Creating forward zone file for $DOMAIN_NAME..."
  cat > "$FORWARD_FILE" <<EOF
\$ORIGIN $DOMAIN_NAME.
\$TTL 3D
@       IN      SOA     $DNS_SUB_DOMAIN.$DOMAIN_NAME. root.$DOMAIN_NAME. (
                        20240401
                        8H
                        2H
                        4W
                        1D )

@       IN      NS      $DNS_SUB_DOMAIN.$DOMAIN_NAME.
@       IN      MX      10 mail.$DOMAIN_NAME.
@       IN      TXT     "DSNM Assignment Server"
@       IN      A       $SERVER_ADDR
mail    IN      A       $MAIL_SERVER_ADDR
www     IN      A       $SERVER_ADDR
$DNS_SUB_DOMAIN     IN      A       $SERVER_ADDR
EOF
else
  log "Forward zone file already exists. Skipping creation."
fi

# Create reverse zone file
REVERSE_FILE="/var/named/${DOMAIN_NAME}.rzone"
if [ ! -f "$REVERSE_FILE" ]; then
  log "Creating reverse zone file for $DOMAIN_NAME..."
  cat > "$REVERSE_FILE" <<EOF
\$ORIGIN $REVERSE_ZONE.
\$TTL 3D
@       IN      SOA     $DNS_SUB_DOMAIN.$DOMAIN_NAME. root.$DOMAIN_NAME. (
                        20240401
                        8H
                        2H
                        4W
                        1D )
@       IN      NS      $DNS_SUB_DOMAIN.$DOMAIN_NAME.
$SERVER_HOST_ID      IN      PTR     $DOMAIN_NAME.
EOF
else
  log "Reverse zone file already exists. Skipping creation."
fi

# Set ownership and permissions
log "Setting ownership and permissions for zone files..."
chown named:named /var/named/${DOMAIN_NAME}.* || err "Failed to set ownership."
chmod 640 /var/named/${DOMAIN_NAME}.* || err "Failed to set permissions."

# Configure firewall
log "Configuring firewall for DNS..."
firewall-cmd --zone=public --add-service=dns --permanent || err "Failed to add DNS service to firewall."
firewall-cmd --reload || err "Failed to reload firewall."

# Start and enable named service
log "Starting and enabling named service..."
systemctl start named || err "Failed to start named."
systemctl enable named || err "Failed to enable named."

log "BIND DNS server setup complete."

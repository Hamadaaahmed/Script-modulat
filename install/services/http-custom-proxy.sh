#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-$(cat /etc/hamada/domain 2>/dev/null || hostname -f 2>/dev/null || hostname)}"

detect_public_ip() {
  local ip=""
  ip="$(cat /etc/hamada/public-ip 2>/dev/null || true)"
  [ -n "$ip" ] || ip="$(curl -4fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"
  [ -n "$ip" ] || ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  printf '%s' "$ip"
}

PUBLIC_IP="${HTTP_CUSTOM_PUBLIC_IP:-$(detect_public_ip)}"

if [ -z "$PUBLIC_IP" ]; then
  echo "[ERROR] Cannot detect public IPv4 address"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y squid >/dev/null

mkdir -p /etc/squid /etc/systemd/system/squid.service.d /etc/hamada
cp -f /etc/squid/squid.conf \
  "/etc/squid/squid.conf.backup.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

cat > /etc/squid/squid.conf <<EOF_SQUID
# HAMADA NET restricted HTTP Custom / Psiphon proxy
#
# Public proxy listeners:
#   gru6.websocket.uk:3128
#   gru6.websocket.uk:8080
#
# Ports 80 and 443 are multiplexed by HAProxy to 127.0.0.1:3128
# only when the first HTTP method is CONNECT.

http_port 127.0.0.1:13128
acl CONNECT method CONNECT

# Only the VPS itself may be used as the tunnel destination.
acl hamada_server dst ${PUBLIC_IP}/32

# Existing SSH/VPN and real Psiphon TCP services.
acl hamada_tunnel_ports port 22
acl hamada_tunnel_ports port 109
acl hamada_tunnel_ports port 143
acl hamada_tunnel_ports port 444
acl hamada_tunnel_ports port 777
acl hamada_tunnel_ports port 1194
acl hamada_tunnel_ports port 8460
acl hamada_tunnel_ports port 10990
acl hamada_tunnel_ports port 10991
acl hamada_tunnel_ports port 10992
acl hamada_tunnel_ports port 10993

http_access allow localhost manager
http_access deny manager

# Accept HTTP Custom CONNECT only to this VPS and approved services.
http_access allow CONNECT hamada_server hamada_tunnel_ports

# Never operate as an unrestricted public proxy.
http_access deny all

cache deny all
via off
forwarded_for delete
request_header_access X-Forwarded-For deny all
request_header_access Via deny all
request_header_access Cache-Control deny all

max_filedescriptors 65535
client_lifetime 12 hours
connect_timeout 15 seconds
forward_timeout 2 minutes

visible_hostname hamada-http-custom-proxy
EOF_SQUID

cat > /etc/systemd/system/squid.service.d/limits.conf <<'EOF_LIMITS'
[Service]
LimitNOFILE=65535
EOF_LIMITS

squid -k parse
systemctl daemon-reload
systemctl enable squid >/dev/null 2>&1 || true
systemctl restart squid

echo "[OK] Restricted HTTP Custom proxy installed"
echo "[OK] Public proxy ports: 3128 and 8080"
echo "[OK] HAProxy backend uses: 127.0.0.1:13128"
echo "[OK] Destination: ${PUBLIC_IP} approved VPN/Psiphon ports only"

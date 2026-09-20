#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-${WIREGUARD_DOMAIN:-}}"
if [ -z "$DOMAIN" ]; then
  DOMAIN="$(cat /etc/hamada/wireguard-domain 2>/dev/null || cat /etc/hamada/domain 2>/dev/null || hostname -I | awk '{print $1}')"
fi

mkdir -p /etc/hamada/wg-accounts /var/www/html/wg-files
rm -f /etc/nginx/conf.d/00-hamada-net-wg-files.conf 2>/dev/null || true
echo "$DOMAIN" > /etc/hamada/wireguard-domain

apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard qrencode iptables curl

SERVER_PRIVATE="/etc/hamada/wg-server-private.key"
SERVER_PUBLIC="/etc/hamada/wg-server-public.key"

if [ ! -s "$SERVER_PRIVATE" ]; then
  wg genkey > "$SERVER_PRIVATE"
  chmod 600 "$SERVER_PRIVATE"
fi

wg pubkey < "$SERVER_PRIVATE" > "$SERVER_PUBLIC"
chmod 600 "$SERVER_PRIVATE"
chmod 644 "$SERVER_PUBLIC"

IFACE="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
IFACE="${IFACE:-eth0}"
echo "$IFACE" > /etc/hamada/wg-interface

cat > /etc/sysctl.d/99-hamada-net-wireguard.conf <<'EOFSYS'
net.ipv4.ip_forward=1
EOFSYS
sysctl --system >/dev/null || true

if command -v hn-wg-sync >/dev/null 2>&1; then
  hn-wg-sync
else
  cat > /etc/wireguard/wg0.conf <<EOFWG
[Interface]
Address = 10.30.0.1/24
ListenPort = 51820
PrivateKey = $(cat "$SERVER_PRIVATE")
PostUp = iptables -t nat -A POSTROUTING -s 10.30.0.0/24 -o $IFACE -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.30.0.0/24 -o $IFACE -j MASQUERADE
SaveConfig = false
EOFWG
  chmod 600 /etc/wireguard/wg0.conf
fi

systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true
if systemctl is-active --quiet wg-quick@wg0; then
  wg syncconf wg0 <(wg-quick strip wg0) >/dev/null 2>&1 || true
else
  systemctl start wg-quick@wg0
fi

echo "[OK] WireGuard configured on UDP 51820."

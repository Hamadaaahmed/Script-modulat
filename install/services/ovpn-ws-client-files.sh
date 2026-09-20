#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-}"
[ -n "$DOMAIN" ] || DOMAIN="$(cat /etc/hamada/domain 2>/dev/null || true)"
[ -n "$DOMAIN" ] || DOMAIN="$(hostname -I | awk '{print $1}')"

DIR="/var/www/html/vpn-files"
BASE="$DIR/client-tcp-1194.ovpn"

if [ ! -f "$BASE" ]; then
  echo "[ERROR] Missing base OpenVPN TCP file: $BASE"
  exit 1
fi

mkdir -p "$DIR"

sed -E "s/^remote .*/remote ${DOMAIN} 443/; s/^proto .*/proto tcp-client/" "$BASE" > "$DIR/ws 443.ovpn"
sed -E "s/^remote .*/remote ${DOMAIN} 80/; s/^proto .*/proto tcp-client/" "$BASE" > "$DIR/ws 80.ovpn"

chmod 644 "$DIR/ws 443.ovpn" "$DIR/ws 80.ovpn"
rm -f "$DIR/openvpn-ws-443.txt"

echo "[OK] OpenVPN WebSocket profiles created:"
echo "     $DIR/ws 443.ovpn"
echo "     $DIR/ws 80.ovpn"

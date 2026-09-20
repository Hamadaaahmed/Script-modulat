#!/usr/bin/env bash
set -euo pipefail

mkdir -p /etc/zivpn /etc/hamada/zivpn-accounts

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)
    ZIVPN_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
    ;;
  *)
    echo "WARNING: ZIVPN currently supported automatically on amd64 only. Arch: $ARCH"
    exit 0
    ;;
esac

echo "Installing ZIVPN UDP server..."

apt-get update -y
apt-get install -y curl wget openssl iptables conntrack ca-certificates

systemctl stop zivpn.service 2>/dev/null || true

rm -f /tmp/zivpn.bin
curl -fL --retry 3 "$ZIVPN_URL" -o /tmp/zivpn.bin
install -m 0755 /tmp/zivpn.bin /usr/local/bin/zivpn
rm -f /tmp/zivpn.bin

if [ ! -f /etc/zivpn/zivpn.key ] || [ ! -f /etc/zivpn/zivpn.crt ]; then
  openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
    -subj "/C=US/ST=VPN/L=HAMADA/O=HAMADA NET/OU=VPN/CN=zivpn" \
    -keyout /etc/zivpn/zivpn.key \
    -out /etc/zivpn/zivpn.crt >/dev/null 2>&1
fi

if [ ! -f /etc/zivpn/config.json ]; then
  cat > /etc/zivpn/config.json <<JSON
{
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": ["zi"]
  }
}
JSON
fi

if [ ! -f /etc/hamada/zivpn-accounts/default.conf ]; then
  DEFAULT_PASS="$(openssl rand -hex 4)"
  EXPIRE_EPOCH="$(date -d "+365 days" +%s)"
  EXPIRE_DATE="$(date -d "@$EXPIRE_EPOCH" "+%Y-%m-%d")"
  cat > /etc/hamada/zivpn-accounts/default.conf <<ACC
username="default"
password="$DEFAULT_PASS"
created="$(date "+%Y-%m-%d")"
expire_epoch="$EXPIRE_EPOCH"
expire_date="$EXPIRE_DATE"
ACC
fi

cat > /etc/systemd/system/zivpn.service <<SERVICE
[Unit]
Description=HAMADA NET ZIVPN UDP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
SERVICE

cat > /usr/local/sbin/hamada-zivpn-firewall <<'FIRE'
#!/usr/bin/env bash
set -e
IFACE="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
[ -n "$IFACE" ] || IFACE="eth0"

sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1 || true
sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1 || true

iptables -t nat -C PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || \
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667

iptables -C INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport 5667 -j ACCEPT

iptables -C INPUT -p udp --dport 6000:19999 -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport 6000:19999 -j ACCEPT

for NET in 169.254.0.0/16 10.20.0.0/24 10.21.0.0/24 10.30.0.0/24; do
  iptables -t nat -C POSTROUTING -s "$NET" -o "$IFACE" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s "$NET" -o "$IFACE" -j MASQUERADE

  iptables -C FORWARD -s "$NET" -o "$IFACE" -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -s "$NET" -o "$IFACE" -j ACCEPT

  iptables -C FORWARD -d "$NET" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -d "$NET" -m state --state RELATED,ESTABLISHED -j ACCEPT
done
FIRE
chmod +x /usr/local/sbin/hamada-zivpn-firewall

cat > /etc/systemd/system/hamada-zivpn-firewall.service <<SERVICE
[Unit]
Description=HAMADA NET ZIVPN Firewall Rules
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hamada-zivpn-firewall
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE

cat > /etc/sysctl.d/98-hamada-zivpn.conf <<SYS
net.core.rmem_max=16777216
net.core.wmem_max=16777216
SYS

sysctl --system >/dev/null 2>&1 || true

systemctl daemon-reload
systemctl enable zivpn.service hamada-zivpn-firewall.service >/dev/null 2>&1 || true
systemctl restart hamada-zivpn-firewall.service || true

if command -v hn-zivpn-sync >/dev/null 2>&1; then
  hn-zivpn-sync || true
else
  systemctl restart zivpn.service || true
fi

echo "ZIVPN UDP installed."

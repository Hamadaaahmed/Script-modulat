#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="${1:-}"
[ -n "$DOMAIN" ] ||
  DOMAIN="$(cat /etc/hamada/domain 2>/dev/null || true)"

ROOT="/usr/local/hamada/ssh/udp-custom"
CONFIG_DIR="/etc/hamada/ssh/udp-custom"

CORE_URL="https://raw.githubusercontent.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64"
UDPGW_URL="https://raw.githubusercontent.com/http-custom/udp-custom/main/module/udpgw"

CORE_PORT="36712"

# HAMADA UDP reservations.
#
# 53          SlowDNS
# 68          system/IPSec related listener on current platform
# 500         IPSec IKE
# 1701        L2TP
# 2200        OpenVPN UDP
# 4500        IPSec NAT-T
# 5667        ZIVPN backend
# 6000-19999  ZIVPN public range
# 10994       Psiphon QUIC
# 51820       WireGuard
EXCLUDED_TEXT="53,68,500,1701,2200,4500,5667,6000-19999,10994,36712,51820"

# UDP Custom's own iptables manager must not capture HAMADA ports.
# HAMADA_UDP_CUSTOM remains the authoritative public-port router.
CORE_EXCLUDE="$EXCLUDED_TEXT"

log() {
  printf '[UDP-CUSTOM] %s\n' "$*"
}

die() {
  printf '[UDP-CUSTOM][ERROR] %s\n' "$*" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] ||
  die "Run as root."

command -v curl >/dev/null 2>&1 ||
  apt-get install -y curl >/dev/null

command -v iptables >/dev/null 2>&1 ||
  apt-get install -y iptables >/dev/null

install -d -m 0755 \
  "$ROOT" \
  "$CONFIG_DIR"

log "Downloading official UDP Custom core..."

CORE_TMP="$(mktemp "${ROOT}/.udp-custom.XXXXXX")"

curl -fL --retry 3 \
  "$CORE_URL" \
  -o "$CORE_TMP"

chmod 0755 "$CORE_TMP"

# Stop only the core before replacing the running executable.
systemctl stop hamada-udp-custom.service 2>/dev/null || true

mv -f "$CORE_TMP" "$ROOT/udp-custom"

log "Downloading official UDPGW..."

UDPGW_TMP="$(mktemp "${ROOT}/.udpgw.XXXXXX")"

curl -fL --retry 3 \
  "$UDPGW_URL" \
  -o "$UDPGW_TMP"

chmod 0755 "$UDPGW_TMP"

systemctl stop hamada-udp-custom-udpgw.service 2>/dev/null || true

mv -f "$UDPGW_TMP" "$ROOT/udpgw"

cat > "$ROOT/config.json" <<EOF_CONFIG
{
  "listen": ":${CORE_PORT}",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords"
  }
}
EOF_CONFIG

cp -f "$ROOT/config.json" "$CONFIG_DIR/config.json"

cat > "$CONFIG_DIR/info.conf" <<EOF_INFO
DOMAIN=${DOMAIN}
CORE_PORT=${CORE_PORT}
PUBLIC_PORTS=1-65535
EXCLUDED=${EXCLUDED_TEXT}
EOF_INFO

chmod 0644 \
  "$ROOT/config.json" \
  "$CONFIG_DIR/config.json" \
  "$CONFIG_DIR/info.conf"

cat > /etc/systemd/system/hamada-udp-custom.service <<EOF_SERVICE
[Unit]
Description=HAMADA UDP Custom Core
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${ROOT}
ExecStart=${ROOT}/udp-custom --exclude ${CORE_EXCLUDE} server
Restart=always
RestartSec=2
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF_SERVICE

cat > /etc/systemd/system/hamada-udp-custom-udpgw.service <<EOF_UDPGW
[Unit]
Description=HAMADA UDP Custom UDPGW
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${ROOT}/udpgw --listen-addr 127.0.0.1:7800 --max-clients 1000 --max-connections-for-client 100
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF_UDPGW

cat > /usr/local/sbin/hamada-udp-custom-firewall <<'EOF_FW'
#!/usr/bin/env bash
set -Eeuo pipefail

CORE_PORT="36712"
CHAIN="HAMADA_UDP_CUSTOM"


IFACE="$(
  ip -4 route show default |
    awk 'NR == 1 {print $5}'
)"

[ -n "$IFACE" ] || {
  echo '[ERROR] WAN interface not found.' >&2
  exit 1
}

# UDP-Custom v1.4 may create its own full-range DNAT rule.
# HAMADA owns UDP dispatching through HAMADA_UDP_CUSTOM, so
# remove every legacy/direct copy before rebuilding our chain.
while iptables -t nat -C PREROUTING \
  -i "$IFACE" \
  -p udp \
  --dport 1:65535 \
  -j DNAT \
  --to-destination :36712 2>/dev/null
do
  iptables -t nat -D PREROUTING \
    -i "$IFACE" \
    -p udp \
    --dport 1:65535 \
    -j DNAT \
    --to-destination :36712
done


# Rebuild our own chain only.
iptables -t nat -N "$CHAIN" 2>/dev/null || true
iptables -t nat -F "$CHAIN"

# Preserve all HAMADA/system UDP services.
for port in \
  53 \
  68 \
  500 \
  1701 \
  2200 \
  4500 \
  5667 \
  10994 \
  36712 \
  51820
do
  iptables -t nat -A "$CHAIN" \
    -p udp --dport "$port" \
    -j RETURN
done

# ZIVPN owns this entire public range.
iptables -t nat -A "$CHAIN" \
  -p udp --dport 6000:19999 \
  -j RETURN

# Everything else goes to the UDP Custom core.
iptables -t nat -A "$CHAIN" \
  -p udp \
  -j REDIRECT --to-ports "$CORE_PORT"

# Attach once to WAN PREROUTING.
iptables -t nat -C PREROUTING \
  -i "$IFACE" \
  -p udp \
  -j "$CHAIN" 2>/dev/null ||
iptables -t nat -A PREROUTING \
  -i "$IFACE" \
  -p udp \
  -j "$CHAIN"

# Filter sees the translated backend port.
iptables -C INPUT \
  -p udp --dport "$CORE_PORT" \
  -j ACCEPT 2>/dev/null ||
iptables -I INPUT \
  -p udp --dport "$CORE_PORT" \
  -j ACCEPT
EOF_FW

chmod 0755 /usr/local/sbin/hamada-udp-custom-firewall

cat > /etc/systemd/system/hamada-udp-custom-firewall.service <<'EOF_FW_UNIT'
[Unit]
Description=HAMADA UDP Custom Full-Port Firewall
After=network-online.target hamada-udp-custom.service hamada-zivpn-firewall.service
Wants=network-online.target hamada-zivpn-firewall.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hamada-udp-custom-firewall
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF_FW_UNIT

systemctl daemon-reload

systemctl enable --now \
  hamada-udp-custom-udpgw.service

systemctl enable --now \
  hamada-udp-custom.service

sleep 1

systemctl enable --now \
  hamada-udp-custom-firewall.service >/dev/null

log "UDP Custom installed."
log "Backend : UDP ${CORE_PORT}"
log "Public  : UDP 1-65535"
log "Exclude : ${EXCLUDED_TEXT}"

#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="${1:-}"
if [[ -z "$DOMAIN" ]]; then
  DOMAIN="$(cat /etc/hamada/domain 2>/dev/null || cat /etc/hamada/domain 2>/dev/null || hostname -f 2>/dev/null || hostname)"
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y curl ca-certificates openssl python3 iptables iproute2 qrencode

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

install -d -m 0755 /etc/hamada/xray /usr/local/etc/xray /var/log/xray /usr/local/lib/hamada
touch /var/log/xray/access.log /var/log/xray/error.log
if getent passwd nobody >/dev/null 2>&1 && getent group nogroup >/dev/null 2>&1; then
  chown nobody:nogroup /var/log/xray /var/log/xray/access.log /var/log/xray/error.log || true
fi
chmod 0755 /var/log/xray
chmod 0644 /var/log/xray/access.log /var/log/xray/error.log
install -m 0755 "$REPO_ROOT/usr/bin/xrayctl" /usr/bin/xrayctl

for cmd in add-xray trial-xray renew-xray del-xray show-xray list-xray xray-status xray-doctor xray-restart xray-menu; do
  install -m 0755 "$REPO_ROOT/usr/bin/$cmd" "/usr/bin/$cmd"
done

if ! command -v xray >/dev/null 2>&1 && [[ ! -x /usr/local/bin/xray ]]; then
  tmp_xray_installer="$(mktemp)"
  curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh -o "$tmp_xray_installer"
  bash "$tmp_xray_installer" install
  rm -f "$tmp_xray_installer"
fi

# Xray service runs as nobody, so use a readable private cert copy.
install -d -m 0755 /etc/hamada/xray/certs
if [ -s /etc/hamada/certs/server.crt ] && [ -s /etc/hamada/certs/server.key ]; then
  cp -L /etc/hamada/certs/server.crt /etc/hamada/xray/certs/xray.crt
  cp -L /etc/hamada/certs/server.key /etc/hamada/xray/certs/xray.key
elif [ -s /etc/ssl/certs/ssl-cert-snakeoil.pem ] && [ -s /etc/ssl/private/ssl-cert-snakeoil.key ]; then
  cp -L /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/hamada/xray/certs/xray.crt
  cp -L /etc/ssl/private/ssl-cert-snakeoil.key /etc/hamada/xray/certs/xray.key
fi
if [ -s /etc/hamada/xray/certs/xray.crt ] && [ -s /etc/hamada/xray/certs/xray.key ]; then
  if getent passwd nobody >/dev/null 2>&1 && getent group nogroup >/dev/null 2>&1; then
    chown nobody:nogroup /etc/hamada/xray/certs/xray.crt /etc/hamada/xray/certs/xray.key || true
  fi
  chmod 0644 /etc/hamada/xray/certs/xray.crt
  chmod 0600 /etc/hamada/xray/certs/xray.key
fi

/usr/bin/xrayctl init "$DOMAIN"

cat >/usr/local/lib/hamada/xray-firewall.sh <<'EOF'
#!/usr/bin/env bash
set -e

add_input() {
  iptables -C INPUT "$@" -j ACCEPT 2>/dev/null || iptables -I INPUT "$@" -j ACCEPT
}

true # Xray TCP is routed through public 80/443 by Nginx/HAProxy
EOF

chmod 0755 /usr/local/lib/hamada/xray-firewall.sh

cat >/etc/systemd/system/hamada-xray-firewall.service <<'EOF'
[Unit]
Description=HAMADA Xray firewall rules
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/lib/hamada/xray-firewall.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now hamada-xray-firewall >/dev/null 2>&1 || true
systemctl enable --now xray >/dev/null 2>&1 || true
systemctl restart xray >/dev/null 2>&1 || true

echo "[OK] Xray installed."
echo "[OK] Presets: xrayctl presets"
echo "[OK] Menu: xray-menu"
echo "[OK] Add: add-xray USER DAYS PRESET"

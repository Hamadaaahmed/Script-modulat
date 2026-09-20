#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-}"
REPO_URL="https://github.com/noobz-id/noobzvpns.git"
WORKDIR="/opt/noobzvpns-src"

echo "[INFO] Installing NoobzVPN Server..."

apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y git curl openssl

rm -rf "$WORKDIR"
git clone --depth=1 "$REPO_URL" "$WORKDIR"

bash "$WORKDIR/install.sh"

mkdir -p /etc/noobzvpns

if [ -n "$DOMAIN" ]; then
  openssl req -new -newkey rsa:2048 -sha256 -days 365 -nodes -x509 \
    -subj "/CN=${DOMAIN}" \
    -keyout /etc/noobzvpns/key.pem \
    -out /etc/noobzvpns/cert.pem
fi


# HAMADA NoobzVPN internal ports fix
python3 - <<'PY2'
from pathlib import Path
p = Path("/etc/noobzvpns/config.toml")
s = p.read_text()
s = s.replace('local_host = ["80"]', 'local_host = ["127.0.0.1:10090"]')
s = s.replace('local_host = ["443"]', 'local_host = ["127.0.0.1:10091"]')
p.write_text(s)
PY2


# HAMADA NoobzVPN stability tuning
python3 - <<'PY2'
from pathlib import Path
p = Path("/etc/noobzvpns/config.toml")
s = p.read_text()

repls = {
  'ip_version = "AUTO"': 'ip_version = "IPv4"',
  'tcp_initial_timeout = 30': 'tcp_initial_timeout = 60',
  'tcp_connect_timeout = 30': 'tcp_connect_timeout = 60',
  'tcp_idle_timeout = 900': 'tcp_idle_timeout = 3600',
  'udp_idle_timeout = 60': 'udp_idle_timeout = 300',
  'device_timeout = 5': 'device_timeout = 60',
}

for old, new in repls.items():
    s = s.replace(old, new)

s = s.replace('local_host = ["80"]', 'local_host = ["127.0.0.1:10090"]')
s = s.replace('local_host = ["443"]', 'local_host = ["127.0.0.1:10091"]')
p.write_text(s)
PY2

systemctl daemon-reload
systemctl enable noobzvpns.service >/dev/null 2>&1 || true
systemctl restart noobzvpns.service

echo "[OK] NoobzVPN installed."
echo "Public Ports: TCP 80 / TCP 443 via HAProxy"

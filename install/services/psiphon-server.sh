#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-$(cat /etc/hamada/domain 2>/dev/null || hostname -f 2>/dev/null || hostname)}"
PSIPHON_DIR="/etc/hamada/psiphon"
EXPORT_DIR="/root/psiphon"
BIN="/usr/local/bin/psiphond"
SERVICE="/etc/systemd/system/hamada-psiphon.service"

detect_ip() {
  local ip=""
  ip="$(cat /etc/hamada/public-ip 2>/dev/null || true)"
  [ -n "$ip" ] || ip="$(curl -4fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"
  [ -n "$ip" ] || ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  printf "%s" "$ip"
}

PUBLIC_IP="${PSIPHON_PUBLIC_IP:-$(detect_ip)}"
if [ -z "$PUBLIC_IP" ]; then
  echo "[ERROR] Cannot detect public IP"
  exit 1
fi

install_deps() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl ca-certificates iproute2
}

install_psiphond() {
  if [ -x "$BIN" ] && "$BIN" -h >/dev/null 2>&1; then
    return 0
  fi

  mkdir -p /usr/local/bin
  local tmp="/tmp/psiphond.$$"
  curl -L --retry 3 --connect-timeout 20 \
    "https://github.com/Psiphon-Labs/psiphon-tunnel-core-binaries/raw/master/psiphond/psiphond" \
    -o "$tmp"

  install -m 755 "$tmp" "$BIN"
  rm -f "$tmp"
}

generate_psiphon() {
  mkdir -p "$PSIPHON_DIR" "$EXPORT_DIR"
  cd "$PSIPHON_DIR"

  if [ "${PSIPHON_FORCE_REGEN:-0}" = "1" ]; then
    rm -f psiphond.config psiphond-osl.config psiphond-tactics.config psiphond-traffic-rules.config server-entry.dat
  fi

  if [ -s server-entry.dat ] && [ -s psiphond.config ]; then
    return 0
  fi

  rm -f psiphond.config psiphond-osl.config psiphond-tactics.config psiphond-traffic-rules.config server-entry.dat

  echo "[INFO] Generating Psiphon server entry for IP: $PUBLIC_IP"

  if ! "$BIN" \
    -ipaddress "$PUBLIC_IP" \
    -protocol SSH:10990 \
    -protocol OSSH:10991 \
    -protocol UNFRONTED-MEEK-OSSH:10992 \
    -protocol UNFRONTED-MEEK-HTTPS-OSSH:10993 \
    -protocol QUIC-OSSH:10994 \
    generate; then

    echo "[WARN] Full protocol generation failed, retrying safe protocols..."
    rm -f psiphond.config psiphond-osl.config psiphond-tactics.config psiphond-traffic-rules.config server-entry.dat

    "$BIN" \
      -ipaddress "$PUBLIC_IP" \
      -protocol OSSH:10991 \
      -protocol UNFRONTED-MEEK-OSSH:10992 \
      -protocol UNFRONTED-MEEK-HTTPS-OSSH:10993 \
      generate
  fi

  if [ ! -s server-entry.dat ]; then
    echo "[ERROR] server-entry.dat was not generated"
    exit 1
  fi

  cp -f server-entry.dat "$EXPORT_DIR/server-entry.dat"
  cp -f server-entry.dat "$EXPORT_DIR/${DOMAIN}-server-entry.dat"

  cat > "$EXPORT_DIR/authorizations.json" <<'JSON'
[]
JSON

  python3 - <<PY
import json
from pathlib import Path

entry = Path("$PSIPHON_DIR/server-entry.dat").read_text().strip()
client = {
    "LocalHttpProxyPort": 8080,
    "LocalSocksProxyPort": 1080,
    "PropagationChannelId": "24BCA4EE20BEB92C",
    "SponsorId": "721AE60D76700F5A",
    "TargetServerEntry": entry
}
Path("$EXPORT_DIR/client.config").write_text(json.dumps(client, indent=2) + "\\n")
PY

  cat > "$EXPORT_DIR/HTTP-CUSTOM-PSIPHON.txt" <<INFO
======================================================
HAMADA NET REAL PSIPHON SERVER
======================================================

HTTP Custom settings:

Enable Psiphon: ON

Protocol:
  ALL
  SSH
  OSSH
  QUIC
  UNFRONTED MEEK
  UNFRONTED MEEK-HTTPS

Regions:
  Best performance

Authorizations:
  []


TargetServerEntry:
$(cat "$PSIPHON_DIR/server-entry.dat")

======================================================
Files:
  /root/psiphon/server-entry.dat
  /root/psiphon/authorizations.json
  /root/psiphon/client.config
  /root/psiphon/HTTP-CUSTOM-PSIPHON.txt

Ports:
  SSH                         TCP 10990
  OSSH                        TCP 10991
  UNFRONTED MEEK              TCP 10992
  UNFRONTED MEEK-HTTPS        TCP 10993
  QUIC                        UDP 10994
======================================================
INFO

  chmod 600 "$EXPORT_DIR"/* 2>/dev/null || true
}

install_service() {
  cat > "$SERVICE" <<EOF_SERVICE
[Unit]
Description=HAMADA NET Real Psiphon Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$PSIPHON_DIR
ExecStart=$BIN run
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF_SERVICE

  systemctl daemon-reload
  systemctl enable hamada-psiphon.service >/dev/null 2>&1 || true
  systemctl restart hamada-psiphon.service
}

install_menu_helper() {
  mkdir -p /usr/local/hamada/bin
  install -m 755 "$0" /usr/local/hamada/bin/psiphon-server.sh 2>/dev/null || true
}

install_deps
install_psiphond
generate_psiphon
install_service
install_menu_helper

echo
echo "[OK] Real Psiphon server installed"
echo "[OK] Service: hamada-psiphon"
echo "[OK] TargetServerEntry: /root/psiphon/server-entry.dat"
echo "[OK] HTTP Custom guide: /root/psiphon/HTTP-CUSTOM-PSIPHON.txt"
echo
systemctl --no-pager --full status hamada-psiphon.service | sed -n '1,18p' || true

#!/usr/bin/env bash
set -Eeuo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$MODULE_DIR/../../.." && pwd)"

green()  { echo "[OK] $*"; }
yellow() { echo "[WARN] $*"; }
die()    { echo "[ERROR] $*" >&2; exit 1; }

need_root() {
  [ "$(id -u)" -eq 0 ] || die "Run SSH module installer as root."
}

detect_domain() {
  DOMAIN="${DOMAIN:-${1:-}}"

  if [ -z "$DOMAIN" ] && [ -s /etc/hamada/domain ]; then
    DOMAIN="$(cat /etc/hamada/domain)"
  fi

  DOMAIN="$(
    printf '%s' "$DOMAIN" |
      sed -E 's#^https?://##; s#/.*$##' |
      tr -d '[:space:]'
  )"

  [ -n "$DOMAIN" ] || die "DOMAIN is required."

  mkdir -p /etc/hamada
  printf '%s\n' "$DOMAIN" > /etc/hamada/domain
  chmod 600 /etc/hamada/domain

  export DOMAIN
}

install_dependencies() {
  yellow "Checking SSH module dependencies..."

  export DEBIAN_FRONTEND=noninteractive

  apt-get update -y
  apt-get install -y \
    openssh-server \
    dropbear \
    stunnel4 \
    openvpn \
    easy-rsa \
    python3 \
    iptables \
    iproute2 \
    procps \
    curl \
    ca-certificates \
    git \
    tar \
    haproxy

  green "SSH module dependencies ready."
}

configure_openssh() {
  local old_ports ssh_password_auth ssh_permit_root f

  mkdir -p /etc/ssh/sshd_config.d /run/sshd
  chmod 755 /run/sshd

  old_ports="$(
    grep -RhsE \
      '^[[:space:]]*Port[[:space:]]+[0-9]+' \
      /etc/ssh/sshd_config \
      /etc/ssh/sshd_config.d/*.conf \
      2>/dev/null |
      awk '{print $2}' |
      sort -u |
      tr '\n' ' ' || true
  )"

  [ -n "$old_ports" ] &&
    yellow "Detected old SSH port(s): $old_ports"

  yellow "Forcing OpenSSH to listen on port 22."

  systemctl stop ssh.socket sshd.socket 2>/dev/null || true
  systemctl disable ssh.socket sshd.socket 2>/dev/null || true
  systemctl unmask ssh.socket sshd.socket 2>/dev/null || true

  # Ubuntu 24.04 may install a persistent ssh.service -> ssh.socket
  # requirement. Remove it so OpenSSH can run as a normal service
  # directly on port 22. This is harmless on Ubuntu 22 and older
  # systems where the dependency does not exist.
  rm -f /etc/systemd/system/ssh.service.requires/ssh.socket
  rm -f /etc/systemd/system/sshd.service.requires/sshd.socket
  systemctl daemon-reload 2>/dev/null || true

  systemctl stop dropbear 2>/dev/null || true
  pkill -x dropbear 2>/dev/null || true

  for f in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
    [ -f "$f" ] || continue

    if [ ! -f "$f.hamada.bak" ]; then
      cp -f "$f" "$f.hamada.bak" 2>/dev/null || true
    fi

    sed -i -E \
      -e 's/^[[:space:]]*Port[[:space:]]+[0-9]+/# HAMADA disabled old Port directive: &/' \
      -e 's/^[[:space:]]*ListenAddress[[:space:]]+.*$/# HAMADA disabled old ListenAddress directive: &/' \
      -e 's/^[[:space:]]*PasswordAuthentication[[:space:]]+.*/# HAMADA disabled old PasswordAuthentication directive: &/' \
      -e 's/^[[:space:]]*PermitRootLogin[[:space:]]+.*/# HAMADA disabled old PermitRootLogin directive: &/' \
      "$f"
  done

  ssh_password_auth="${HAMADA_SSH_PASSWORD_AUTH:-yes}"
  ssh_permit_root="${HAMADA_SSH_PERMIT_ROOT:-yes}"

  cat > /etc/ssh/sshd_config.d/99-hamada.conf <<EOFSSH
Port 22
AddressFamily inet
ListenAddress 0.0.0.0
PasswordAuthentication ${ssh_password_auth}
PermitRootLogin ${ssh_permit_root}
UsePAM yes
EOFSSH

  sshd -t || die "Invalid OpenSSH configuration."

  systemctl daemon-reload 2>/dev/null || true
  systemctl enable ssh.service >/dev/null 2>&1 || true
  systemctl reset-failed ssh.service sshd.service 2>/dev/null || true

  timeout 20 systemctl restart ssh.service 2>/dev/null ||
    timeout 20 systemctl restart sshd.service 2>/dev/null ||
    die "OpenSSH failed to restart."

  sleep 1

  if ss -lntup | grep -Eq 'sshd.*:22|:22[[:space:]]'; then
    green "OpenSSH configured on port 22."
  else
    systemctl status ssh.service --no-pager -l || true
    die "OpenSSH port 22 is not listening."
  fi
}

configure_dropbear() {
  cat > /etc/default/dropbear <<'DROPBEAR'
NO_START=0
DROPBEAR_PORT=109
DROPBEAR_EXTRA_ARGS="-p 109 -p 143"
DROPBEAR_BANNER="/etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
DROPBEAR_KEEPALIVE=300
DROPBEAR_IDLE_TIMEOUT=0
DROPBEAR

  echo "Welcome to HAMADA SSH Server" > /etc/issue.net

  systemctl enable dropbear >/dev/null 2>&1 || true
  systemctl restart dropbear

  green "Dropbear configured on ports 109 and 143."
}

install_ws_bridge() {
  mkdir -p /usr/local/hamada/bin

  cat > /usr/local/hamada/bin/ws-bridge.py <<'PY'
#!/usr/bin/env python3
import select
import socket
import sys
import threading

listen_host = sys.argv[1]
listen_port = int(sys.argv[2])
target_host = sys.argv[3]
target_port = int(sys.argv[4])

RESPONSE = (
    b"HTTP/1.1 101 Switching Protocols\r\n"
    b"Upgrade: websocket\r\n"
    b"Connection: Upgrade\r\n"
    b"\r\n"
)


def pipe(a, b):
    sockets = [a, b]

    try:
        while True:
            readable, _, errored = select.select(
                sockets,
                [],
                sockets,
                300,
            )

            if errored:
                break

            if not readable:
                break

            for sock in readable:
                data = sock.recv(8192)

                if not data:
                    return

                other = b if sock is a else a
                other.sendall(data)

    except Exception:
        pass


def handle(client):
    upstream = None

    try:
        client.settimeout(10)
        first = b""

        while b"\r\n\r\n" not in first and len(first) < 16384:
            chunk = client.recv(4096)

            if not chunk:
                return

            first += chunk

        upstream = socket.create_connection(
            (target_host, target_port),
            timeout=10,
        )

        if (
            first.startswith(b"GET ")
            or b"Upgrade:" in first
            or b"upgrade:" in first
        ):
            client.sendall(RESPONSE)
        else:
            upstream.sendall(first)

        client.settimeout(None)
        upstream.settimeout(None)

        pipe(client, upstream)

    except Exception:
        pass

    finally:
        try:
            client.close()
        except Exception:
            pass

        if upstream:
            try:
                upstream.close()
            except Exception:
                pass


srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind((listen_host, listen_port))
srv.listen(200)

while True:
    client, _ = srv.accept()
    threading.Thread(
        target=handle,
        args=(client,),
        daemon=True,
    ).start()
PY

  chmod 0755 /usr/local/hamada/bin/ws-bridge.py

  cat > /etc/systemd/system/hamada-ssh-ws.service <<'EOFSSHWS'
[Unit]
Description=HAMADA SSH WebSocket Bridge
After=network.target ssh.service

[Service]
ExecStart=/usr/bin/python3 /usr/local/hamada/bin/ws-bridge.py 127.0.0.1 10080 127.0.0.1 22
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOFSSHWS

  cat > /etc/systemd/system/hamada-dropbear-ws.service <<'EOFDROPWS'
[Unit]
Description=HAMADA Dropbear WebSocket Bridge
After=network.target dropbear.service

[Service]
ExecStart=/usr/bin/python3 /usr/local/hamada/bin/ws-bridge.py 127.0.0.1 10081 127.0.0.1 109
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOFDROPWS

  cat > /etc/systemd/system/hamada-openvpn-ws.service <<'EOFOVPNWS'
[Unit]
Description=HAMADA OpenVPN WebSocket Bridge
After=network.target openvpn-server@server-tcp-1194.service

[Service]
ExecStart=/usr/bin/python3 /usr/local/hamada/bin/ws-bridge.py 127.0.0.1 10082 127.0.0.1 1194
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOFOVPNWS

  systemctl daemon-reload

  systemctl enable --now hamada-ssh-ws.service
  systemctl enable --now hamada-dropbear-ws.service

  green "SSH, Dropbear and OpenVPN WebSocket units installed."
}

configure_openvpn() {
  local plugin iface ca

  mkdir -p \
    /etc/openvpn/server \
    /var/www/html/vpn-files \
    /etc/hamada/openvpn

  if [ ! -d /etc/openvpn/easy-rsa ]; then
    make-cadir /etc/openvpn/easy-rsa
  fi

  pushd /etc/openvpn/easy-rsa >/dev/null

  if [ ! -d pki ]; then
    EASYRSA_BATCH=1 ./easyrsa init-pki
    EASYRSA_BATCH=1 \
      EASYRSA_REQ_CN="HAMADA-CA" \
      ./easyrsa build-ca nopass

    EASYRSA_BATCH=1 ./easyrsa gen-dh
    EASYRSA_BATCH=1 ./easyrsa build-server-full server nopass
  fi

  cp -f pki/ca.crt /etc/openvpn/server/ca.crt
  cp -f pki/issued/server.crt /etc/openvpn/server/server.crt
  cp -f pki/private/server.key /etc/openvpn/server/server.key
  cp -f pki/dh.pem /etc/openvpn/server/dh.pem

  popd >/dev/null

  plugin="/usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so"

  [ -f "$plugin" ] ||
    plugin="/usr/lib/openvpn/openvpn-plugin-auth-pam.so"

  [ -f "$plugin" ] ||
    die "OpenVPN PAM authentication plugin was not found."

  cat > /etc/openvpn/server/server-tcp-1194.conf <<EOFTCP
port 1194
proto tcp4
dev tun
ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key /etc/openvpn/server/server.key
dh /etc/openvpn/server/dh.pem
server 10.8.0.0 255.255.255.0
keepalive 10 120
persist-key
persist-tun
user nobody
group nogroup
plugin $plugin login
verify-client-cert none
username-as-common-name
status /etc/openvpn/server/openvpn-tcp.log
verb 3
EOFTCP

  cat > /etc/openvpn/server/server-udp-2200.conf <<EOFUDP
port 2200
proto udp4
dev tun
ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key /etc/openvpn/server/server.key
dh /etc/openvpn/server/dh.pem
server 10.9.0.0 255.255.255.0
keepalive 10 120
persist-key
persist-tun
user nobody
group nogroup
plugin $plugin login
verify-client-cert none
username-as-common-name
status /etc/openvpn/server/openvpn-udp.log
verb 3
EOFUDP

  sysctl -w net.ipv4.ip_forward=1 >/dev/null

  grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf ||
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

  cat > /usr/local/sbin/hamada-openvpn-firewall <<'EOFOVPNFW'
#!/usr/bin/env bash
set -Eeuo pipefail

IFACE="$(
  ip -4 route show default |
    awk 'NR == 1 {print $5}'
)"

[ -n "$IFACE" ] || {
  echo '[ERROR] OpenVPN WAN interface not found.' >&2
  exit 1
}

sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true

for NET in 10.8.0.0/24 10.9.0.0/24; do
  iptables -t nat -C POSTROUTING \
    -s "$NET" -o "$IFACE" -j MASQUERADE 2>/dev/null ||
  iptables -t nat -A POSTROUTING \
    -s "$NET" -o "$IFACE" -j MASQUERADE
done
EOFOVPNFW

  chmod 0755 /usr/local/sbin/hamada-openvpn-firewall

  cat > /etc/systemd/system/hamada-openvpn-firewall.service <<'EOFOVPNFWSVC'
[Unit]
Description=HAMADA NET OpenVPN firewall rules
After=network-online.target
Wants=network-online.target
Before=openvpn-server@server-tcp-1194.service openvpn-server@server-udp-2200.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hamada-openvpn-firewall
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOFOVPNFWSVC

  systemctl daemon-reload
  systemctl enable --now hamada-openvpn-firewall.service

  ca="$(cat /etc/openvpn/server/ca.crt)"

  cat > /var/www/html/vpn-files/client-tcp-1194.ovpn <<EOFTCPCLIENT
client
dev tun
proto tcp-client
remote $DOMAIN 1194
resolv-retry infinite
nobind
persist-key
persist-tun
auth-user-pass
remote-cert-tls server
verb 3
<ca>
$ca
</ca>
EOFTCPCLIENT

  cat > /var/www/html/vpn-files/client-udp-2200.ovpn <<EOFUDPCLIENT
client
dev tun
proto udp
remote $DOMAIN 2200
resolv-retry infinite
nobind
persist-key
persist-tun
auth-user-pass
remote-cert-tls server
verb 3
<ca>
$ca
</ca>
EOFUDPCLIENT

  cat > /var/www/html/vpn-files/openvpn-ws-443.txt <<EOFWSINFO
OPENVPN WEBSOCKET TLS

Host    : $DOMAIN
Port    : 443
Path    : /openvpn
Payload : GET /openvpn HTTP/1.1[crlf]Host: $DOMAIN[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]

Use with client-tcp-1194.ovpn username/password account.
EOFWSINFO

  systemctl enable --now \
    openvpn-server@server-tcp-1194.service

  systemctl enable --now \
    openvpn-server@server-udp-2200.service

  systemctl enable --now \
    hamada-openvpn-ws.service

  if [ -f "$PROJECT_ROOT/install/services/ovpn-ws-client-files.sh" ]; then
    bash \
      "$PROJECT_ROOT/install/services/ovpn-ws-client-files.sh" \
      "$DOMAIN"
  fi

  green "OpenVPN TCP/UDP/WebSocket configured."
}

configure_stunnel() {
  [ -s /etc/hamada/certs/server.crt ] ||
    die "Missing /etc/hamada/certs/server.crt"

  [ -s /etc/hamada/certs/server.key ] ||
    die "Missing /etc/hamada/certs/server.key"

  mkdir -p /etc/stunnel

  cat > /etc/stunnel/hamada.conf <<EOFSTUNNEL
cert = /etc/hamada/certs/server.crt
key = /etc/hamada/certs/server.key
client = no
foreground = no

[ssh-tls]
accept = 444
connect = 127.0.0.1:22

[dropbear-tls]
accept = 777
connect = 127.0.0.1:109
EOFSTUNNEL

  sed -i \
    's/^ENABLED=.*/ENABLED=1/' \
    /etc/default/stunnel4 2>/dev/null ||
    echo "ENABLED=1" > /etc/default/stunnel4

  systemctl enable stunnel4 >/dev/null 2>&1 || true
  systemctl restart stunnel4

  green "Stunnel configured on ports 444 and 777."
}


install_udp_custom() {
  local installer="$PROJECT_ROOT/install/modules/ssh/services/udp-custom.sh"

  [ -f "$installer" ] ||
    die "UDP Custom installer not found: $installer"

  bash "$installer" "$DOMAIN"

  green "UDP Custom installed as part of SSH module."
}

install_slowdns() {
  local installer="$PROJECT_ROOT/install/services/slowdns.sh"

  if [ "${HAMADA_INSTALL_SLOWDNS:-1}" != "1" ]; then
    yellow "SlowDNS disabled by HAMADA_INSTALL_SLOWDNS."
    return 0
  fi

  [ -f "$installer" ] ||
    die "SlowDNS installer not found: $installer"

  DOMAIN="$DOMAIN" \
  SLOWDNS_DOMAIN_BASE="$DOMAIN" \
    bash "$installer" "$DOMAIN"

  green "SlowDNS installed as part of SSH module."
}

verify_service() {
  local service="$1"

  if systemctl is-active --quiet "$service"; then
    printf '  [OK] %-45s active\n' "$service"
    return 0
  fi

  printf '  [FAIL] %s\n' "$service"
  systemctl status "$service" --no-pager -l 2>/dev/null || true
  return 1
}

verify_port_tcp() {
  local port="$1"

  if ss -lnt |
     awk '{print $4}' |
     grep -Eq "[:.]${port}$"; then
    printf '  [OK] TCP %-5s listening\n' "$port"
    return 0
  fi

  printf '  [FAIL] TCP %s not listening\n' "$port"
  return 1
}

verify_port_udp() {
  local port="$1"

  if ss -lnu |
     awk '{print $4}' |
     grep -Eq "[:.]${port}$"; then
    printf '  [OK] UDP %-5s listening\n' "$port"
    return 0
  fi

  printf '  [FAIL] UDP %s not listening\n' "$port"
  return 1
}

verify_ssh_module() {
  local failures=0

  echo
  echo "============================================"
  echo "        SSH MODULE VERIFICATION"
  echo "============================================"

  for service in \
    ssh.service \
    dropbear.service \
    hamada-ssh-ws.service \
    hamada-dropbear-ws.service \
    hamada-openvpn-ws.service \
    openvpn-server@server-tcp-1194.service \
    openvpn-server@server-udp-2200.service \
    hamada-udp-custom.service \
    hamada-udp-custom-udpgw.service \
    hamada-udp-custom-firewall.service \
    stunnel4.service
  do
    verify_service "$service" || failures=$((failures + 1))
  done

  if [ "${HAMADA_INSTALL_SLOWDNS:-1}" = "1" ]; then
    verify_service hamada-slowdns.service ||
      failures=$((failures + 1))

    verify_service hamada-slowdns-mux.service ||
      failures=$((failures + 1))
  fi

  echo
  echo "Ports:"
  echo "--------------------------------------------"

  for port in \
    22 \
    109 \
    143 \
    444 \
    777 \
    1194 \
    10080 \
    10081 \
    10082
  do
    verify_port_tcp "$port" ||
      failures=$((failures + 1))
  done

  verify_port_udp 2200 ||
    failures=$((failures + 1))

  verify_port_udp 36712 ||
    failures=$((failures + 1))

  if [ "${HAMADA_INSTALL_SLOWDNS:-1}" = "1" ]; then
    verify_port_udp 53 ||
      failures=$((failures + 1))
  fi

  echo "============================================"

  if [ "$failures" -ne 0 ]; then
    die "SSH module verification failed: $failures check(s)."
  fi

  green "SSH module verification passed."
}

install_ssh_module() {
  need_root
  detect_domain "${1:-}"

  echo "============================================"
  echo "         HAMADA NET SSH MODULE"
  echo "============================================"
  echo "Domain: $DOMAIN"
  echo "============================================"

  install_dependencies

  configure_openssh
  configure_dropbear
  install_ws_bridge
  configure_openvpn
  install_udp_custom
  configure_stunnel
  install_slowdns
  verify_ssh_module

  mkdir -p /etc/hamada/modules
  printf '%s\n' "installed" > /etc/hamada/modules/ssh

  green "SSH + OpenVPN + SlowDNS module installation completed."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  install_ssh_module "${1:-}"
fi

#!/bin/bash
set -euo pipefail

hamada_restart_ssh22() {
  mkdir -p /run/sshd
  chmod 755 /run/sshd

  systemctl stop ssh.socket sshd.socket 2>/dev/null || true
  systemctl disable ssh.socket sshd.socket 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true

  sshd -t || die "Invalid OpenSSH config after forcing port 22."

  if ss -H -lntp 'sport = :22' 2>/dev/null | grep -q 'sshd'; then
    systemctl reset-failed ssh.service sshd.service 2>/dev/null || true
    green "OpenSSH already listening on port 22."
    return 0
  fi

  if ss -H -lntp 'sport = :22' 2>/dev/null | grep -q 'dropbear'; then
    systemctl stop dropbear 2>/dev/null || true
    sleep 1
  fi

  systemctl reset-failed ssh.service sshd.service 2>/dev/null || true
  timeout 15 systemctl restart ssh.service 2>/dev/null || \
  timeout 15 systemctl restart sshd.service 2>/dev/null || \
  die "OpenSSH service failed to restart on port 22."
}


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

green(){ echo "[OK] $*"; }
yellow(){ echo "[WARN] $*"; }
die(){ echo "[ERROR] $*" >&2; exit 1; }

ui_line(){ echo "============================================"; }
ui_header(){
  clear
  ui_line
  echo "        HAMADA NET VIP VPN INSTALLER"
  ui_line
}
ui_step(){
  local current="$1"
  local total="$2"
  local name="$3"
  echo
  ui_line
  printf " [%02d/%02d] %s\n" "$current" "$total" "$name"
  ui_line
}

need_root() {
  [ "$(id -u)" = "0" ] || die "Run as root."
}

detect_domain() {
  mkdir -p /etc/hamada /etc/v2ray

  ip="$(curl -4fsS https://api.ipify.org || true)"
  fallback_domain=""
  [ -n "$ip" ] && fallback_domain="${ip}.sslip.io"

  clean_domain() {
    echo "$1" | sed -E 's#^https?://##; s#/.*$##' | tr -d ' 
	'
  }

  valid_domain() {
    d="$1"
    echo "$d" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$'
  }

  echo
  echo "============================================"
  echo "           DOMAIN CONFIGURATION"
  echo "============================================"
  echo "Enter the full Cloudflare domain on the same line."
  echo "Example: gru6.websocket.uk"
  echo "Leave empty to use: ${fallback_domain}"
  echo "============================================"

  if [ -n "${DOMAIN:-}" ]; then
    DOMAIN="$(clean_domain "$DOMAIN")"
    valid_domain "$DOMAIN" || die "Invalid DOMAIN value: $DOMAIN"
  else
    while true; do
      read -rp "Domain: " input_domain
      input_domain="$(clean_domain "$input_domain")"

      if [ -z "$input_domain" ]; then
        input_domain="$fallback_domain"
      fi

      if valid_domain "$input_domain"; then
        DOMAIN="$input_domain"
        break
      fi

      echo
      echo "[ERROR] Invalid domain: $input_domain"
      echo "You must enter the full domain on the same line. Example:"
      echo "gru6.websocket.uk"
      echo
    done
  fi

  [ -n "$DOMAIN" ] || die "Domain is empty and public IPv4 could not be detected."

  printf '%s
' "$DOMAIN" > /etc/hamada/domain
  printf '%s
' "$DOMAIN" > /root/domain
  printf '%s
' "$DOMAIN" > /etc/v2ray/domain

  A_DOMAIN="${A_DOMAIN:-$(cat /etc/hamada/a-domain 2>/dev/null || printf '%s' "$DOMAIN")}"
  SLOWDNS_NS_DOMAIN="${SLOWDNS_NS_DOMAIN:-$(cat /etc/hamada/slowdns-ns 2>/dev/null || true)}"
  [ -n "$SLOWDNS_NS_DOMAIN" ] || SLOWDNS_NS_DOMAIN="ns-${DOMAIN%%.*}.${DOMAIN#*.}"

  WIREGUARD_DOMAIN="${WIREGUARD_DOMAIN:-$(cat /etc/hamada/wireguard-domain 2>/dev/null || printf '%s' "$DOMAIN")}"

  valid_domain "$A_DOMAIN" || die "Invalid A record hostname: $A_DOMAIN"
  valid_domain "$SLOWDNS_NS_DOMAIN" || die "Invalid SlowDNS NS hostname: $SLOWDNS_NS_DOMAIN"
  valid_domain "$WIREGUARD_DOMAIN" || die "Invalid WireGuard domain: $WIREGUARD_DOMAIN"

  printf '%s\n' "$A_DOMAIN" > /etc/hamada/a-domain
  printf '%s\n' "$SLOWDNS_NS_DOMAIN" > /etc/hamada/slowdns-ns
  printf '%s\n' "$WIREGUARD_DOMAIN" > /etc/hamada/wireguard-domain
  chmod 600 /etc/hamada/domain /etc/hamada/a-domain /etc/hamada/slowdns-ns /etc/hamada/wireguard-domain

  export DOMAIN A_DOMAIN SLOWDNS_NS_DOMAIN WIREGUARD_DOMAIN

  green "Main domain: $DOMAIN"
  green "A record: $A_DOMAIN"
  green "SlowDNS NS: $SLOWDNS_NS_DOMAIN"
  green "WireGuard domain: $WIREGUARD_DOMAIN"
}


disable_ipv6() {
  cat > /etc/sysctl.d/99-hamada-disable-ipv6.conf <<'EOFIPV6'
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
EOFIPV6

  sysctl -p /etc/sysctl.d/99-hamada-disable-ipv6.conf >/dev/null 2>&1 || true

  if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -P INPUT DROP 2>/dev/null || true
    ip6tables -P FORWARD DROP 2>/dev/null || true
    ip6tables -P OUTPUT DROP 2>/dev/null || true
  fi

  green "IPv6 disabled."
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive

  apt-get update
  apt-get install -y \
    apt-transport-https software-properties-common \
    curl wget git ca-certificates openssl lsb-release gnupg \
    jq unzip zip tar gzip bzip2 nano vim \
    dnsutils netcat-openbsd socat uuid-runtime cron \
    nginx haproxy openssh-server dropbear stunnel4 squid \
    openvpn easy-rsa python3 python3-pip certbot python3-certbot-nginx \
    iptables iproute2 net-tools psmisc procps \
    build-essential make gcc g++ pkg-config golang-go

  green "Packages installed."
}

install_reset_tool() {
  rm -f /usr/bin/hamada-cloudflare /usr/bin/menu-domain
  install -m 0755 "$REPO_DIR/usr/bin/hamada-reset" /usr/bin/hamada-reset
  install -m 0755 "$REPO_DIR/usr/bin/hamada-restore-defaults" /usr/bin/hamada-restore-defaults
  install -m 0755 "$REPO_DIR/usr/bin/hamada-speedtest" /usr/bin/hamada-speedtest
  install -m 0755 "$REPO_DIR/usr/bin/menu-settings" /usr/bin/menu-settings
  green "Reset tool installed."
}

configure_ssh() {
  mkdir -p /etc/ssh/sshd_config.d /run/sshd
  chmod 755 /run/sshd

  old_ports="$(grep -RhsE '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | sort -u | tr '\n' ' ' || true)"
  [ -n "$old_ports" ] && yellow "Detected old SSH port(s): $old_ports"

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
    cp -f "$f" "$f.hamada.bak" 2>/dev/null || true
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

  sshd -t || die "Invalid OpenSSH config after forcing port 22."

  systemctl daemon-reload 2>/dev/null || true
  systemctl enable ssh.service >/dev/null 2>&1 || true
  systemctl reset-failed ssh.service sshd.service 2>/dev/null || true

  timeout 20 systemctl restart ssh.service 2>/dev/null || timeout 20 systemctl restart sshd.service 2>/dev/null || die "OpenSSH service failed to restart on port 22."

  sleep 1
  echo "OpenSSH listening ports:"
  ss -lntup | grep -E 'sshd|:22' || true

  if ss -lntup | grep -Eq 'sshd.*:22|:22[[:space:]]'; then
    green "OpenSSH configured on port 22."
  else
    systemctl status ssh.service --no-pager || true
    die "OpenSSH service is active but port 22 is not listening."
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


configure_certs() {
  local cert_dir="/etc/hamada/certs"
  local live_dir="/etc/letsencrypt/live/$DOMAIN"
  local live_crt="$live_dir/fullchain.pem"
  local live_key="$live_dir/privkey.pem"
  local current_crt="$cert_dir/server.crt"
  local current_key="$cert_dir/server.key"
  local is_sslip_domain=0

  mkdir -p "$cert_dir" /etc/letsencrypt/live

  certificate_public_hash() {
    openssl x509 \
      -in "$1" \
      -pubkey \
      -noout 2>/dev/null |
      openssl pkey \
        -pubin \
        -outform DER 2>/dev/null |
      sha256sum |
      awk '{print $1}'
  }

  private_key_public_hash() {
    openssl pkey \
      -in "$1" \
      -pubout \
      -outform DER 2>/dev/null |
      sha256sum |
      awk '{print $1}'
  }

  certificate_key_match() {
    local crt="$1"
    local key="$2"
    local cert_hash
    local key_hash

    cert_hash="$(certificate_public_hash "$crt")" ||
      return 1

    key_hash="$(private_key_public_hash "$key")" ||
      return 1

    [ -n "$cert_hash" ] &&
      [ "$cert_hash" = "$key_hash" ]
  }

  certificate_usable_for_domain() {
    local crt="$1"
    local key="$2"

    [ -s "$crt" ] &&
      [ -s "$key" ] &&
      openssl x509 \
        -in "$crt" \
        -noout \
        -checkhost "$DOMAIN" \
        -checkend 86400 >/dev/null 2>&1 &&
      certificate_key_match "$crt" "$key"
  }

  certificate_is_self_signed() {
    local crt="$1"
    local subject
    local issuer

    subject="$(
      openssl x509 \
        -in "$crt" \
        -noout \
        -subject \
        -nameopt RFC2253 2>/dev/null |
      sed 's/^subject=//'
    )" || return 1

    issuer="$(
      openssl x509 \
        -in "$crt" \
        -noout \
        -issuer \
        -nameopt RFC2253 2>/dev/null |
      sed 's/^issuer=//'
    )" || return 1

    [ -n "$subject" ] &&
      [ "$subject" = "$issuer" ]
  }

  prepare_haproxy_certificate() {
    local temporary_pem

    [ -s "$current_crt" ] ||
      die "TLS certificate file is missing."

    [ -s "$current_key" ] ||
      die "TLS private key file is missing."

    certificate_key_match "$current_crt" "$current_key" ||
      die "TLS certificate and private key do not match."

    temporary_pem="$(
      mktemp "$cert_dir/.haproxy.pem.XXXXXX"
    )"

    if ! cat "$current_crt" "$current_key" \
      > "$temporary_pem"
    then
      rm -f "$temporary_pem"
      die "Could not build the HAProxy certificate bundle."
    fi

    chmod 600 "$temporary_pem"

    mv -f \
      "$temporary_pem" \
      "$cert_dir/haproxy.pem"
  }

  backup_replaced_certificate_files() {
    local name
    local backup_dir=""
    local found=0

    for name in server.crt server.key haproxy.pem; do
      if [ -e "$cert_dir/$name" ] ||
         [ -L "$cert_dir/$name" ]; then
        found=1
        break
      fi
    done

    [ "$found" -eq 1 ] || return 0

    backup_dir="$(
      printf \
        '/root/hamada-backups/certificate-replaced-%s' \
        "$(date +%Y%m%d-%H%M%S)"
    )"

    mkdir -p "$backup_dir"

    for name in server.crt server.key haproxy.pem; do
      if [ -e "$cert_dir/$name" ] ||
         [ -L "$cert_dir/$name" ]; then
        cp -a \
          "$cert_dir/$name" \
          "$backup_dir/$name"
      fi
    done

    yellow "Previous unusable certificate retained: $backup_dir"
  }

  make_self_signed_certificate() {
    local reason="${1:-no usable certificate}"
    local temporary_dir

    backup_replaced_certificate_files

    temporary_dir="$(
      mktemp -d "$cert_dir/.selfsigned.XXXXXX"
    )"

    yellow \
      "Creating self-signed certificate for $DOMAIN ($reason)."

    openssl req \
      -x509 \
      -nodes \
      -newkey rsa:2048 \
      -days 3650 \
      -keyout "$temporary_dir/server.key" \
      -out "$temporary_dir/server.crt" \
      -subj "/CN=${DOMAIN}" \
      >/dev/null 2>&1

    chmod 600 "$temporary_dir/server.key"

    install -m 0600 \
      "$temporary_dir/server.key" \
      "$current_key"

    install -m 0644 \
      "$temporary_dir/server.crt" \
      "$current_crt"

    rm -rf "$temporary_dir"
  }

  echo "$DOMAIN" |
    grep -Eq '(^|[.])sslip[.]io$' &&
    is_sslip_domain=1

  if certificate_usable_for_domain \
    "$live_crt" \
    "$live_key"
  then
    ln -sfn "$live_crt" "$current_crt"
    ln -sfn "$live_key" "$current_key"

    green \
      "Existing trusted certificate reused for $DOMAIN."

  elif certificate_usable_for_domain \
    "$current_crt" \
    "$current_key"
  then
    if certificate_is_self_signed "$current_crt"; then
      if [ "${HAMADA_STRICT_LE:-0}" = "1" ] &&
         [ "${HAMADA_CERT_MODE:-auto}" != "selfsigned" ] &&
         [ "$is_sslip_domain" -ne 1 ]
      then
        die \
          "Strict TLS mode requires a trusted certificate for $DOMAIN."
      fi

      yellow \
        "Existing matching self-signed certificate preserved; it was not regenerated."
    else
      green \
        "Existing valid certificate preserved for $DOMAIN."
    fi

  else
    if [ "${HAMADA_STRICT_LE:-0}" = "1" ] &&
       [ "${HAMADA_CERT_MODE:-auto}" != "selfsigned" ] &&
       [ "$is_sslip_domain" -ne 1 ]
    then
      die \
        "No valid trusted certificate exists for $DOMAIN. Complete Cloudflare setup before strict installation."
    fi

    if [ "${HAMADA_CERT_MODE:-auto}" = "selfsigned" ] ||
       [ "$is_sslip_domain" -eq 1 ]
    then
      make_self_signed_certificate \
        "self-signed mode or sslip.io test domain"
    else
      make_self_signed_certificate \
        "trusted issuance is deferred until HAProxy setup is complete"
    fi
  fi

  prepare_haproxy_certificate

  echo "Certificate info:"
  openssl x509 \
    -in "$current_crt" \
    -noout \
    -subject \
    -issuer \
    -dates ||
    true
}


issue_trusted_certificate() {
  local cert_dir="/etc/hamada/certs"
  local live_dir="/etc/letsencrypt/live/$DOMAIN"
  local live_crt="$live_dir/fullchain.pem"
  local live_key="$live_dir/privkey.pem"
  local temporary_pem
  local is_sslip_domain=0

  echo "$DOMAIN" |
    grep -Eq '(^|[.])sslip[.]io$' &&
    is_sslip_domain=1

  if [ "${HAMADA_CERT_MODE:-auto}" = "selfsigned" ] ||
     [ "$is_sslip_domain" -eq 1 ]
  then
    yellow "Trusted certificate issuance skipped for $DOMAIN."
    return 0
  fi

  mkdir -p \
    /var/www/html/.well-known/acme-challenge \
    "$cert_dir"

  if ! certbot certonly \
      --webroot \
      --webroot-path /var/www/html \
      --domain "$DOMAIN" \
      --non-interactive \
      --agree-tos \
      --register-unsafely-without-email \
      --keep-until-expiring
  then
    if [ "${HAMADA_STRICT_LE:-0}" = "1" ]; then
      die "Let's Encrypt certificate issuance failed for $DOMAIN."
    fi

    yellow \
      "Let's Encrypt issuance failed; temporary certificate remains active."
    return 0
  fi

  [ -s "$live_crt" ] ||
    die "Let's Encrypt fullchain is missing for $DOMAIN."

  [ -s "$live_key" ] ||
    die "Let's Encrypt private key is missing for $DOMAIN."

  certificate_key_match "$live_crt" "$live_key" ||
    die "Let's Encrypt certificate and private key do not match."

  ln -sfn "$live_crt" "$cert_dir/server.crt"
  ln -sfn "$live_key" "$cert_dir/server.key"

  temporary_pem="$(
    mktemp "$cert_dir/.haproxy.pem.XXXXXX"
  )"

  if ! cat "$live_crt" "$live_key" > "$temporary_pem"; then
    rm -f "$temporary_pem"
    die "Could not build trusted HAProxy certificate bundle."
  fi

  chmod 600 "$temporary_pem"
  mv -f "$temporary_pem" "$cert_dir/haproxy.pem"

  haproxy -c -f /etc/haproxy/haproxy.cfg

  systemctl reload haproxy

  if systemctl is-active --quiet stunnel4 2>/dev/null; then
    systemctl reload stunnel4 2>/dev/null ||
      systemctl restart stunnel4
  fi

  systemctl enable --now certbot.timer >/dev/null 2>&1 || true

  green "Trusted Let's Encrypt certificate active for $DOMAIN."
}


install_ws_bridge() {
  mkdir -p /usr/local/hamada/bin

  cat > /usr/local/hamada/bin/ws-bridge.py <<'PY'
#!/usr/bin/env python3
import socket
import select
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
            readable, _, errored = select.select(sockets, [], sockets, 300)
            if errored:
                break
            if not readable:
                break
            for s in readable:
                data = s.recv(8192)
                if not data:
                    return
                other = b if s is a else a
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

        upstream = socket.create_connection((target_host, target_port), timeout=10)

        if first.startswith(b"GET ") or b"Upgrade:" in first or b"upgrade:" in first:
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
    c, _ = srv.accept()
    threading.Thread(target=handle, args=(c,), daemon=True).start()
PY

  chmod +x /usr/local/hamada/bin/ws-bridge.py

  cat > /etc/systemd/system/hamada-ssh-ws.service <<'EOFWS1'
[Unit]
Description=HAMADA SSH WebSocket Bridge
After=network.target ssh.service

[Service]
ExecStart=/usr/bin/python3 /usr/local/hamada/bin/ws-bridge.py 127.0.0.1 10080 127.0.0.1 22
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOFWS1

  cat > /etc/systemd/system/hamada-dropbear-ws.service <<'EOFWS2'
[Unit]
Description=HAMADA Dropbear WebSocket Bridge
After=network.target dropbear.service

[Service]
ExecStart=/usr/bin/python3 /usr/local/hamada/bin/ws-bridge.py 127.0.0.1 10081 127.0.0.1 109
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOFWS2

  cat > /etc/systemd/system/hamada-openvpn-ws.service <<'EOFWS3'
[Unit]
Description=HAMADA OpenVPN WebSocket Bridge
After=network.target openvpn-server@server-tcp-1194.service

[Service]
ExecStart=/usr/bin/python3 /usr/local/hamada/bin/ws-bridge.py 127.0.0.1 10082 127.0.0.1 1194
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOFWS3

  systemctl daemon-reload
  systemctl enable --now hamada-ssh-ws.service
  systemctl enable --now hamada-dropbear-ws.service
  green "WebSocket bridges installed."
}

configure_nginx() {
  systemctl stop nginx haproxy apache2 2>/dev/null || true
  fuser -k 80/tcp 443/tcp 8080/tcp 3128/tcp 2>/dev/null || true

  rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/hamada-ssh.conf /etc/nginx/conf.d/ssh.conf /etc/nginx/conf.d/vpn.conf

  cat > /etc/nginx/conf.d/hamada-ssh.conf <<'EOFNGINX'
server {
    # Public 80/443 are owned by HAProxy and forwarded here.
    listen 127.0.0.1:8088 proxy_protocol;
    listen 127.0.0.1:8089 http2 proxy_protocol;

    # Trust only the local HAProxy hop and restore the real client IP.
    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    # Pass the verified client IP to all Xray HTTP and gRPC transports.

    server_name _;
    root /var/www/html;

    # Download files must stay before generic WS routes.
    location ^~ /vpn-files/ {
        alias /var/www/html/vpn-files/;
        autoindex on;
        add_header Cache-Control "no-store";
    }

    location ^~ /payloads/ {
        alias /var/www/html/payloads/;
        autoindex off;
        default_type text/plain;
        try_files $uri =404;
    }

    location ^~ /wg-files/ {
        alias /var/www/html/wg-files/;
        autoindex off;
        default_type application/octet-stream;
        add_header Content-Disposition "attachment";
        try_files $uri =404;
    }

    location = /hamada-ca.crt {
        default_type application/x-x509-ca-cert;
        add_header Content-Disposition "attachment; filename=hamada-ca.crt";
        alias /var/www/html/hamada-ca.crt;
    }

    # Xray over public 80 and 443 via HAProxy/Nginx multi-port.
    location ^~ /vless-ws {
        proxy_pass http://127.0.0.1:8447;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    location ^~ /vless-grpc {
        grpc_read_timeout 86400s;
        grpc_send_timeout 86400s;
        grpc_pass grpc://127.0.0.1:8448;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $remote_addr;
    }

    location ^~ /vless-xhttp {
        proxy_pass http://127.0.0.1:8449;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    location ^~ /vless-hu {
        proxy_pass http://127.0.0.1:8451;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    location ^~ /vmess-ws {
        proxy_pass http://127.0.0.1:8455;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    location ^~ /vmess-grpc {
        grpc_read_timeout 86400s;
        grpc_send_timeout 86400s;
        grpc_pass grpc://127.0.0.1:8456;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $remote_addr;
    }

    location ^~ /vmess-xhttp {
        proxy_pass http://127.0.0.1:8457;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    location ^~ /vmess-hu {
        proxy_pass http://127.0.0.1:8458;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    location ^~ /trojan-ws {
        proxy_pass http://127.0.0.1:8461;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    location ^~ /trojangrpc {
        grpc_read_timeout 86400s;
        grpc_send_timeout 86400s;
        grpc_pass grpc://127.0.0.1:8462;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $remote_addr;
    }

    location ^~ /trojan-xhttp {
        proxy_pass http://127.0.0.1:8463;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    location ^~ /trojan-hu {
        proxy_pass http://127.0.0.1:8464;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    location ^~ /ss-ws {
        proxy_pass http://127.0.0.1:8467;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    location ^~ /ss-grpc {
        grpc_read_timeout 86400s;
        grpc_send_timeout 86400s;
        grpc_pass grpc://127.0.0.1:8468;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $remote_addr;
    }

    # Let's Encrypt HTTP-01 challenge. Keep this before generic/root routes.
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/html;
        default_type text/plain;
        try_files $uri =404;
    }

    # SSH WebSocket. Exact "/" is intentionally routed to SSH WS for HTTP Custom root payloads.
    location = / {
        proxy_pass http://127.0.0.1:10080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    location ~ ^/(ssh|ws)$ {
        proxy_pass http://127.0.0.1:10080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    location ~ ^/(dropbear|db)$ {
        proxy_pass http://127.0.0.1:10081;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    location ~ ^/(openvpn|ovpn|vpn)$ {
        proxy_pass http://127.0.0.1:10082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/html;
        default_type text/plain;
        try_files $uri =404;
    }

    location / {
        default_type text/plain;
        return 200 "HAMADA NGINX OK\n";
    }
}
EOFNGINX

  nginx -t
  systemctl enable nginx >/dev/null 2>&1 || true
  systemctl restart nginx
  green "Nginx internal routing configured on 127.0.0.1:8088/8089."
}

configure_stunnel() {
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

  sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4 2>/dev/null || echo "ENABLED=1" > /etc/default/stunnel4
  systemctl enable stunnel4 >/dev/null 2>&1 || true
  systemctl restart stunnel4
  green "Stunnel configured on 444 and 777. Public 443 remains for Nginx."
}

configure_openvpn() {
  mkdir -p /etc/openvpn/server /var/www/html/vpn-files /etc/hamada/openvpn

  if [ ! -d /etc/openvpn/easy-rsa ]; then
    make-cadir /etc/openvpn/easy-rsa
  fi

  pushd /etc/openvpn/easy-rsa >/dev/null

  if [ ! -d pki ]; then
    EASYRSA_BATCH=1 ./easyrsa init-pki
    EASYRSA_BATCH=1 EASYRSA_REQ_CN="HAMADA-CA" ./easyrsa build-ca nopass
    EASYRSA_BATCH=1 ./easyrsa gen-dh
    EASYRSA_BATCH=1 ./easyrsa build-server-full server nopass
  fi

  cp -f pki/ca.crt /etc/openvpn/server/ca.crt
  cp -f pki/issued/server.crt /etc/openvpn/server/server.crt
  cp -f pki/private/server.key /etc/openvpn/server/server.key
  cp -f pki/dh.pem /etc/openvpn/server/dh.pem

  plugin="/usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so"
  [ -f "$plugin" ] || plugin="/usr/lib/openvpn/openvpn-plugin-auth-pam.so"

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
  grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

  iface="$(ip route | awk '/default/ {print $5; exit}')"
  iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o "$iface" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$iface" -j MASQUERADE
  iptables -t nat -C POSTROUTING -s 10.9.0.0/24 -o "$iface" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.9.0.0/24 -o "$iface" -j MASQUERADE

  ca="$(cat /etc/openvpn/server/ca.crt)"

  cat > /var/www/html/vpn-files/client-tcp-1194.ovpn <<EOFC1
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
EOFC1

  cat > /var/www/html/vpn-files/client-udp-2200.ovpn <<EOFC2
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
EOFC2

  cat > /var/www/html/vpn-files/openvpn-ws-443.txt <<EOFC3
OPENVPN WEBSOCKET TLS

Host    : $DOMAIN
Port    : 443
Path    : /openvpn
Payload : GET /openvpn HTTP/1.1[crlf]Host: $DOMAIN[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]

Use with client-tcp-1194.ovpn username/password account.
EOFC3

  systemctl enable --now openvpn-server@server-tcp-1194.service
  systemctl enable --now openvpn-server@server-udp-2200.service
  systemctl enable --now hamada-openvpn-ws.service

  popd >/dev/null

  green "OpenVPN TCP/UDP and WS bridge configured."
}

configure_squid() {
  bash "$REPO_DIR/install/services/http-custom-proxy.sh" "$DOMAIN"
  green "Restricted HTTP Custom proxy configured on 3128 and 8080."
}

install_user_scripts() {
  find "$REPO_DIR/usr/bin" -maxdepth 1 -type f -exec install -m 0755 {} /usr/bin/ \;

  # Refresh client/profile generators and optional services after scripts are installed.
  bash "$REPO_DIR/install/services/ovpn-ws-client-files.sh" "$DOMAIN"
  bash "$REPO_DIR/install/services/l2tp-ipsec.sh" "$DOMAIN"
  bash "$REPO_DIR/install/services/wireguard.sh" "$WIREGUARD_DOMAIN"
  bash "$REPO_DIR/install/services/zivpn.sh"
  bash "$REPO_DIR/install/services/xray.sh" "$DOMAIN"
  if [ -f "$REPO_DIR/install/services/noobzvpn.sh" ]; then
    bash "$REPO_DIR/install/services/noobzvpn.sh" "$DOMAIN" || yellow "NoobzVPN setup failed. Run: bash $REPO_DIR/install/services/noobzvpn.sh"
  fi
  if [ -f "$REPO_DIR/install/services/psiphon-server.sh" ]; then
    bash "$REPO_DIR/install/services/psiphon-server.sh" "$DOMAIN" || yellow "Psiphon server setup failed. Run: bash $REPO_DIR/install/services/psiphon-server.sh"
  fi

  command -v hamada-wg-web-fix >/dev/null 2>&1 && hamada-wg-web-fix || true
  command -v hamada-net-fix-network >/dev/null 2>&1 && hamada-net-fix-network || true

  green "Menu, account scripts, L2TP, WireGuard, ZIVPN, and Xray installed."
}

configure_root_auto_menu() {
  local bashrc="/root/.bashrc"

  if ! grep -qF "# HAMADA NET AUTO MENU" "$bashrc" 2>/dev/null; then
    cat >> "$bashrc" <<'EOFAUTOMENU'

# HAMADA NET AUTO MENU
if [[ $- == *i* ]] \
  && [ -t 0 ] \
  && [ -t 1 ] \
  && [ "$(id -u)" -eq 0 ] \
  && [ -z "${HAMADA_MENU_STARTED:-}" ] \
  && command -v menu >/dev/null 2>&1; then
  export HAMADA_MENU_STARTED=1
  clear
  menu
fi
EOFAUTOMENU
  fi

  green "Automatic root login menu configured."
}

schedule_install_reboot() {
  if [ "${HAMADA_NO_REBOOT:-0}" = "1" ]; then
    green "Automatic reboot skipped because HAMADA_NO_REBOOT=1."
    return 0
  fi

  green "Server will reboot automatically in 10 seconds."

  if command -v systemd-run >/dev/null 2>&1; then
    systemd-run \
      --unit=hamada-install-reboot \
      --on-active=10s \
      /usr/bin/systemctl reboot >/dev/null
  else
    nohup bash -c 'sleep 10; /sbin/reboot' \
      >/dev/null 2>&1 &
  fi
}

clean_previous_install_if_needed() {
  local uninstall_tool="$REPO_DIR/usr/bin/hamada-uninstall"
  local detected=0

  # New installations will have the marker below.
  [ -f /etc/hamada/.installed ] && detected=1

  # Backward-compatible detection for installations created before
  # the marker existed.

  systemctl cat hamada-ssh-ws.service >/dev/null 2>&1 && detected=1 || true
  systemctl cat xray.service >/dev/null 2>&1 && [ -d /etc/hamada ] && detected=1 || true

  [ "$detected" -eq 1 ] || return 0

  ui_line
  yellow "Existing HAMADA NET installation detected."
  yellow "Cleaning previous installation before reinstall..."
  ui_line

  [ -f "$uninstall_tool" ] || die "Missing reinstall cleaner: $uninstall_tool"

  HAMADA_PROJECT_ROOT="$REPO_DIR" \
    bash "$uninstall_tool" --reinstall --yes

  green "Previous HAMADA NET installation cleaned."
  ui_line
}

main() {
  local resume_from="${HAMADA_RESUME_FROM_STEP:-1}"

  ui_header
  need_root

  case "$resume_from" in
    1)
      clean_previous_install_if_needed

      ui_step 1 12 "Domain configuration"
      detect_domain

      ui_step 2 12 "System packages"
      install_packages

      ui_step 3 12 "Network hardening"
      disable_ipv6
      install_reset_tool

      ui_step 4 12 "TLS certificates"
      configure_certs

      ui_step 5 12 "SSH + OpenVPN + SlowDNS Module"
      bash "$REPO_DIR/install/modules/ssh/install.sh" "$DOMAIN"

      ui_step 6 12 "SSH WebSocket bridge"
      green "Included in SSH module."
      ;;
    7)
      yellow "Resume mode enabled: continuing installation from step 7."

      [ -s /etc/hamada/domain ] || die "Cannot resume: missing /etc/hamada/domain."
      [ -f /etc/hamada/modules/ssh ] || die "Cannot resume: SSH module marker is missing."

      DOMAIN="$(cat /etc/hamada/domain)"
      A_DOMAIN="$(cat /etc/hamada/a-domain 2>/dev/null || printf '%s' "$DOMAIN")"
      SLOWDNS_NS_DOMAIN="$(cat /etc/hamada/slowdns-ns 2>/dev/null || true)"
      WIREGUARD_DOMAIN="$(cat /etc/hamada/wireguard-domain 2>/dev/null || printf 'wg.%s' "$DOMAIN")"

      systemctl is-active --quiet ssh || die "Cannot resume: SSH service is not active."
      systemctl is-active --quiet hamada-ssh-ws.service || die "Cannot resume: SSH WebSocket service is not active."
      systemctl is-active --quiet hamada-udp-custom.service || die "Cannot resume: UDP Custom service is not active."
      systemctl is-active --quiet hamada-udp-custom-firewall.service || die "Cannot resume: UDP Custom firewall service is not active."
      systemctl is-active --quiet hamada-slowdns.service || die "Cannot resume: SlowDNS service is not active."

      green "Resume prerequisites verified."
      ;;
    *)
      die "Unsupported HAMADA_RESUME_FROM_STEP=$resume_from. Supported values: 1 or 7."
      ;;
  esac

  ui_step 7 12 "Nginx and HAProxy"
  configure_nginx
  bash "$REPO_DIR/install/services/haproxy-443.sh" "$DOMAIN"
  issue_trusted_certificate

  ui_step 8 12 "Stunnel SSL"
  green "Included in SSH module."

  ui_step 9 12 "OpenVPN"
  green "Included in SSH module."

  ui_step 10 12 "HTTP Custom proxy"
  configure_squid

  ui_step 11 12 "VPN account tools and services"
  install_user_scripts

  ui_step 12 12 "System health check"
  hamada-doctor || yellow "Doctor reported issues; check service logs after reboot."
}

main "$@"


# HAMADA SlowDNS / DNSTT
# SlowDNS is installed and verified by install/modules/ssh/install.sh.

mkdir -p /etc/hamada
touch /etc/hamada/.installed
chmod 600 /etc/hamada/.installed

configure_root_auto_menu

ui_line
green "HAMADA NET installation completed successfully."
ui_line

schedule_install_reboot

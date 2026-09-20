#!/usr/bin/env bash
set -euo pipefail

green(){ echo "[OK] $*"; }
yellow(){ echo "[WARN] $*"; }
die(){ echo "[ERROR] $*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "Run as root."

DOMAIN="${SLOWDNS_DOMAIN_BASE:-${DOMAIN:-${1:-}}}"
if [ -z "$DOMAIN" ] && [ -s /etc/hamada/domain ]; then
  DOMAIN="$(cat /etc/hamada/domain)"
fi
if [ -z "$DOMAIN" ] && [ -s /root/domain ]; then
  DOMAIN="$(cat /root/domain)"
fi
[ -n "$DOMAIN" ] || die "DOMAIN is required."

DOMAIN="$(echo "$DOMAIN" | sed -E 's#^https?://##; s#/.*$##' | tr -d '[:space:]')"

default_slowdns_domain() {
  local d="$1"
  local first rest
  first="${d%%.*}"
  rest="${d#*.}"
  if [ "$first" != "$rest" ]; then
    echo "ns-${first}.${rest}"
  else
    echo "ns.${d}"
  fi
}

SLOWDNS_DOMAIN="${SLOWDNS_DOMAIN:-}"
if [ -z "$SLOWDNS_DOMAIN" ] && [ -s /etc/hamada/slowdns-domain ]; then
  SLOWDNS_DOMAIN="$(cat /etc/hamada/slowdns-domain)"
fi
if [ -z "$SLOWDNS_DOMAIN" ]; then
  SLOWDNS_DOMAIN="$(default_slowdns_domain "$DOMAIN")"
fi
SLOWDNS_DOMAIN="$(echo "$SLOWDNS_DOMAIN" | sed -E 's#^https?://##; s#/.*$##' | tr -d '[:space:]')"

SLOWDNS_NS_HOST="${SLOWDNS_NS_HOST:-}"
if [ -z "$SLOWDNS_NS_HOST" ] && [ -s /etc/hamada/slowdns-ns-host ]; then
  SLOWDNS_NS_HOST="$(cat /etc/hamada/slowdns-ns-host)"
fi
if [ -z "$SLOWDNS_NS_HOST" ]; then
  SLOWDNS_NS_HOST="$DOMAIN"
fi
SLOWDNS_NS_HOST="$(echo "$SLOWDNS_NS_HOST" | sed -E 's#^https?://##; s#/.*$##' | tr -d '[:space:]')"

SLOWDNS_MTU="${SLOWDNS_MTU:-}"
SLOWDNS_SSH_UPSTREAM="${SLOWDNS_SSH_UPSTREAM:-127.0.0.1:109}"
SLOWDNS_XRAY_UPSTREAM="${SLOWDNS_XRAY_UPSTREAM:-127.0.0.1:443}"
SLOWDNS_MUX_ADDR="${SLOWDNS_MUX_ADDR:-127.0.0.1:53001}"

PUBLIC_IP="${PUBLIC_IP:-}"
if [ -z "$PUBLIC_IP" ]; then
  PUBLIC_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"
fi
if [ -z "$PUBLIC_IP" ]; then
  PUBLIC_IP="$(curl -4fsS https://api.ipify.org || true)"
fi
[ -n "$PUBLIC_IP" ] || die "Could not detect public IPv4."

mkdir -p /etc/hamada/slowdns /var/log/hamada
printf '%s\n' "$SLOWDNS_DOMAIN" > /etc/hamada/slowdns-domain
printf '%s\n' "$SLOWDNS_NS_HOST" > /etc/hamada/slowdns-ns-host

cleanup_old_slowdns_modes() {
  systemctl disable --now badvpn-udpgw 2>/dev/null || true
  rm -f /etc/systemd/system/badvpn-udpgw.service
  rm -f /etc/sysctl.d/99-hamada-slowdns-speed.conf

  if [ -s /etc/hamada/slowdns/dnstt-build-id ]; then
    yellow "Removing patched DNSTT marker."
    rm -f /etc/hamada/slowdns/dnstt-build-id
  fi
}

go_version_ok() {
  command -v go >/dev/null 2>&1 || return 1
  local ver major minor
  ver="$(go version | awk '{print $3}' | sed 's/^go//')"
  major="${ver%%.*}"
  minor="${ver#*.}"
  minor="${minor%%.*}"
  minor="${minor%%[^0-9]*}"
  [ -n "$major" ] && [ -n "$minor" ] || return 1
  [ "$major" -gt 1 ] && return 0
  [ "$major" -eq 1 ] && [ "$minor" -ge 21 ]
}

install_modern_go() {
  export PATH="/usr/local/go/bin:$PATH"
  if go_version_ok; then
    green "Go version OK: $(go version)"
    return 0
  fi

  local go_version arch url tmp_tar
  go_version="${GO_VERSION:-1.26.4}"

  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "Unsupported CPU architecture for Go: $(uname -m)" ;;
  esac

  url="https://go.dev/dl/go${go_version}.linux-${arch}.tar.gz"
  tmp_tar="$(mktemp)"
  yellow "Installing Go ${go_version} from go.dev"
  curl -fsSL "$url" -o "$tmp_tar"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$tmp_tar"
  rm -f "$tmp_tar"
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  export PATH="/usr/local/go/bin:$PATH"
  green "Go installed: $(go version)"
}

install_dnstt_server() {
  if [ "${SLOWDNS_REBUILD_DNSTT:-0}" = "1" ]; then
    rm -f /usr/local/bin/dnstt-server /usr/bin/dnstt-server
  fi

  if command -v dnstt-server >/dev/null 2>&1; then
    green "dnstt-server already installed."
    return 0
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y git ca-certificates curl tar haproxy
  install_modern_go

  local tmp
  tmp="$(mktemp -d)"
  if ! git clone --depth=1 https://www.bamsoftware.com/git/dnstt.git "$tmp/dnstt"; then
    yellow "Shallow clone failed; retrying full DNSTT clone."
    rm -rf "$tmp/dnstt"
    git clone https://www.bamsoftware.com/git/dnstt.git "$tmp/dnstt"
  fi

  (cd "$tmp/dnstt/dnstt-server" && go build -o /usr/local/bin/dnstt-server .)
  chmod 0755 /usr/local/bin/dnstt-server
  rm -rf "$tmp"
  green "dnstt-server installed."
}

cleanup_old_slowdns_modes
install_dnstt_server

if [ ! -s /etc/hamada/slowdns/server.key ] || [ ! -s /etc/hamada/slowdns/server.pub ]; then
  /usr/local/bin/dnstt-server -gen-key \
    -privkey-file /etc/hamada/slowdns/server.key \
    -pubkey-file /etc/hamada/slowdns/server.pub
  chmod 600 /etc/hamada/slowdns/server.key
  chmod 644 /etc/hamada/slowdns/server.pub
  green "SlowDNS keys generated."
fi

cat > /etc/hamada/slowdns/haproxy-mux.cfg <<EOF_MUX
global
    log /dev/log local0
    maxconn 20000

defaults
    mode tcp
    log global
    option dontlognull
    option clitcpka
    option srvtcpka
    timeout connect 10s
    timeout client  24h
    timeout server  24h
    timeout tunnel  24h
    timeout client-fin 30s
    timeout server-fin 30s

frontend slowdns_ssh_xray_mux
    bind ${SLOWDNS_MUX_ADDR}
    tcp-request inspect-delay 5s
    tcp-request content accept if { req.ssl_hello_type 1 }
    tcp-request content accept if { req.payload(0,4) -m str SSH- }
    use_backend ssh_109 if { req.payload(0,4) -m str SSH- }
    use_backend xray_tls443 if { req.ssl_hello_type 1 }
    default_backend xray_tls443

backend ssh_109
    server ssh ${SLOWDNS_SSH_UPSTREAM} check

backend xray_tls443
    server xraytls ${SLOWDNS_XRAY_UPSTREAM} check
EOF_MUX

cat > /etc/systemd/system/hamada-slowdns-mux.service <<'EOF_MUX_SERVICE'
[Unit]
Description=HAMADA SlowDNS SSH/Xray TCP Mux
After=network.target haproxy.service xray.service dropbear.service
Wants=haproxy.service xray.service dropbear.service

[Service]
ExecStart=/usr/sbin/haproxy -f /etc/hamada/slowdns/haproxy-mux.cfg -Ws
Restart=always
RestartSec=2
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF_MUX_SERVICE

SLOWDNS_MTU_ARG=""
if [ -n "$SLOWDNS_MTU" ]; then
  SLOWDNS_MTU_ARG="-mtu ${SLOWDNS_MTU}"
fi

cat > /etc/systemd/system/hamada-slowdns.service <<EOF_SERVICE
[Unit]
Description=HAMADA SlowDNS DNSTT Server for SSH and Xray
After=network.target hamada-slowdns-mux.service
Wants=hamada-slowdns-mux.service

[Service]
ExecStart=/usr/local/bin/dnstt-server ${SLOWDNS_MTU_ARG} -udp ${PUBLIC_IP}:53 -privkey-file /etc/hamada/slowdns/server.key ${SLOWDNS_DOMAIN} ${SLOWDNS_MUX_ADDR}
Restart=always
RestartSec=2
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF_SERVICE

iptables -C INPUT -p udp --dport 53 -j ACCEPT >/dev/null 2>&1 || iptables -I INPUT -p udp --dport 53 -j ACCEPT >/dev/null 2>&1 || true

systemctl daemon-reload
systemctl enable hamada-slowdns-mux hamada-slowdns >/dev/null 2>&1 || true
systemctl restart hamada-slowdns-mux
systemctl restart hamada-slowdns

PUBKEY="$(tr -d '\n\r ' < /etc/hamada/slowdns/server.pub)"

cat > /etc/hamada/slowdns/info.txt <<EOF_INFO
SlowDNS / DNSTT

Tunnel Domain : ${SLOWDNS_DOMAIN}
NS Host       : ${SLOWDNS_NS_HOST}
Public Key    : ${PUBKEY}
DNS           : 8.8.8.8 or 1.1.1.1
UDP Port      : 53
MTU           : ${SLOWDNS_MTU:-dnstt-default}
Mux           : ${SLOWDNS_MUX_ADDR}
SSH Upstream  : ${SLOWDNS_SSH_UPSTREAM}
Xray Upstream : ${SLOWDNS_XRAY_UPSTREAM}

Cloudflare DNS only:
A  ${SLOWDNS_NS_HOST} -> ${PUBLIC_IP}
NS ${SLOWDNS_DOMAIN} -> ${SLOWDNS_NS_HOST}

Mode:
SlowDNS -> SSH and Xray mux

HTTP Custom Xray:
Enable DNS : ON
SlowDNS    : ON
V2Ray      : ON
SSH        : OFF
UDPGW      : OFF
Recommended: VLESS WS TLS 443

HTTP Custom SSH:
Enable DNS : ON
SlowDNS    : ON
SSH        : ON
V2Ray      : OFF
UDPGW      : OFF
SSH Port   : 109
EOF_INFO

green "SlowDNS installed."
cat /etc/hamada/slowdns/info.txt

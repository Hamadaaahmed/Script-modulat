#!/bin/bash
set -euo pipefail

DOMAIN="${1:-}"

green(){ echo "[OK] $*"; }
yellow(){ echo "[WARN] $*"; }
die(){ echo "[ERROR] $*" >&2; exit 1; }

[ -n "$DOMAIN" ] || die "Domain argument is required."

export DEBIAN_FRONTEND=noninteractive

apt-get update -y >/dev/null 2>&1 || true
apt-get install -y haproxy

# Some failed/purged installs can leave the haproxy binary available while
# /etc/haproxy is missing. Always recreate the config directory before writing.
mkdir -p /etc/haproxy /etc/hamada/certs

[ -f /etc/hamada/certs/server.crt ] || die "Missing /etc/hamada/certs/server.crt"
[ -f /etc/hamada/certs/server.key ] || die "Missing /etc/hamada/certs/server.key"
cat /etc/hamada/certs/server.crt /etc/hamada/certs/server.key > /etc/hamada/certs/haproxy.pem
chmod 600 /etc/hamada/certs/haproxy.pem

yellow "Moving public TLS 443 from Nginx to HAProxy."

systemctl stop nginx haproxy apache2 2>/dev/null || true
fuser -k 80/tcp 443/tcp 8080/tcp 3128/tcp 2>/dev/null || true
sleep 1

mkdir -p /etc/nginx/hamada-disabled

for f in /etc/nginx/sites-enabled/*; do
  [ -e "$f" ] || continue
  mv -f "$f" /etc/nginx/hamada-disabled/ 2>/dev/null || true
done

for f in /etc/nginx/conf.d/*; do
  [ -e "$f" ] || continue
  [ "$(basename "$f")" = "hamada-ssh.conf" ] && continue
  mv -f "$f" /etc/nginx/hamada-disabled/ 2>/dev/null || true
done

rm -f /etc/nginx/conf.d/hamada-ssh.conf

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

fuser -k 443/tcp 80/tcp 8080/tcp 3128/tcp 2>/dev/null || true
sleep 1
if ss -lntp | grep -q ':443'; then
  echo "[ERROR] Port 443 is still busy before HAProxy starts:"
  ss -lntp | grep ':443' || true
  die "Nginx or another service is still using port 443."
fi

if [ -f /etc/haproxy/haproxy.cfg ] && [ ! -f /etc/haproxy/haproxy.cfg.hamada.bak ]; then
  cp -f /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.hamada.bak
fi
cat > /etc/haproxy/haproxy.cfg <<'EOF'
global
    log /dev/log local0
    daemon
    maxconn 12000

defaults
    log global
    mode tcp
    option dontlognull
    timeout connect 30s
    timeout client 4h
    timeout server 4h

frontend hamada_public_80
    bind *:80
    mode tcp

    stick-table type ip size 100k expire 10m store conn_cur,conn_rate(10s)
    tcp-request connection track-sc0 src
    tcp-request connection reject if { sc0_conn_cur gt 120 }
    tcp-request connection reject if { sc0_conn_rate gt 240 }

    tcp-request inspect-delay 30s
    acl proxy_connect req.payload(0,7) -m str CONNECT
    tcp-request content accept if proxy_connect
    tcp-request content accept if { req.len ge 7 }

    acl noobz_payload req.payload(0,20) -m sub /noobzvpn
    use_backend hamada_noobz_internal if noobz_payload
    use_backend hamada_squid_internal if proxy_connect
    default_backend hamada_nginx_internal

frontend hamada_public_443
    bind *:443
    mode tcp

    stick-table type ip size 100k expire 10m store conn_cur,conn_rate(10s)
    tcp-request connection track-sc0 src
    tcp-request connection reject if { sc0_conn_cur gt 120 }
    tcp-request connection reject if { sc0_conn_rate gt 240 }

    tcp-request inspect-delay 30s
    acl proxy_connect req.payload(0,7) -m str CONNECT
    acl tls_clienthello req.ssl_hello_type 1
    tcp-request content accept if proxy_connect
    tcp-request content accept if tls_clienthello

    use_backend hamada_squid_internal if proxy_connect
    default_backend hamada_tls_terminator

frontend hamada_public_8080
    bind *:8080
    mode tcp

    stick-table type ip size 100k expire 10m store conn_cur,conn_rate(10s)
    tcp-request connection track-sc0 src
    tcp-request connection reject if { sc0_conn_cur gt 15 }
    tcp-request connection reject if { sc0_conn_rate gt 30 }

    default_backend hamada_squid_internal

frontend hamada_public_3128
    bind *:3128
    mode tcp

    stick-table type ip size 100k expire 10m store conn_cur,conn_rate(10s)
    tcp-request connection track-sc0 src
    tcp-request connection reject if { sc0_conn_cur gt 15 }
    tcp-request connection reject if { sc0_conn_rate gt 30 }

    default_backend hamada_squid_internal

backend hamada_tls_terminator
    mode tcp
    server local_tls 127.0.0.1:11443 send-proxy-v2

frontend hamada_tls_443_internal
    bind 127.0.0.1:11443 accept-proxy ssl crt /etc/hamada/certs/haproxy.pem alpn h2,http/1.1
    mode tcp
    tcp-request inspect-delay 30s
    tcp-request content accept if { req.len gt 0 }

    acl http_get      req.payload(0,3) -m str GET
    acl http_post     req.payload(0,4) -m str POST
    acl http_head     req.payload(0,4) -m str HEAD
    acl http_put      req.payload(0,3) -m str PUT
    acl http_options  req.payload(0,7) -m str OPTIONS
    acl http_delete   req.payload(0,6) -m str DELETE
    acl client_h2     ssl_fc_alpn -i h2
    acl http2_preface req.payload(0,3) -m str PRI

    acl noobz_payload req.payload(0,20) -m sub /noobzvpn
    use_backend hamada_noobz_internal if noobz_payload
    use_backend hamada_nginx_internal if http_get
    use_backend hamada_nginx_internal if http_post
    use_backend hamada_nginx_internal if http_head
    use_backend hamada_nginx_internal if http_put
    use_backend hamada_nginx_internal if http_options
    use_backend hamada_nginx_internal if http_delete
    use_backend hamada_nginx_h2_internal if client_h2
    use_backend hamada_nginx_h2_internal if http2_preface

    default_backend hamada_dropbear_tls_direct

backend hamada_noobz_internal
    mode tcp
    server noobz10090 127.0.0.1:10090

backend hamada_squid_internal
    mode tcp
    server squid13128 127.0.0.1:13128

backend hamada_nginx_internal
    mode tcp
    server nginx8088 127.0.0.1:8088 send-proxy-v2

backend hamada_nginx_h2_internal
    mode tcp
    server nginx8089 127.0.0.1:8089 send-proxy-v2

backend hamada_dropbear_tls_direct
    mode tcp
    server dropbear109 127.0.0.1:109
EOF
haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl enable haproxy >/dev/null 2>&1 || true
systemctl stop haproxy nginx squid apache2 2>/dev/null || true
fuser -k 80/tcp 443/tcp 8080/tcp 3128/tcp 2>/dev/null || true
pkill -9 haproxy 2>/dev/null || true
systemctl reset-failed haproxy 2>/dev/null || true
sleep 2
systemctl restart haproxy
systemctl restart nginx

mkdir -p /etc/letsencrypt/renewal-hooks/deploy

{
  printf '#!/usr/bin/env bash\nset -euo pipefail\nDOMAIN=%q\n' "$DOMAIN"

  cat <<'EOFHOOK'
CERT_DIR="/etc/hamada/certs"
LINEAGE="/etc/letsencrypt/live/$DOMAIN"
TEMP_PEM=""

[ -s "$LINEAGE/fullchain.pem" ] || exit 0
[ -s "$LINEAGE/privkey.pem" ] || exit 0

ln -sfn "$LINEAGE/fullchain.pem" "$CERT_DIR/server.crt"
ln -sfn "$LINEAGE/privkey.pem" "$CERT_DIR/server.key"

TEMP_PEM="$(
  mktemp "$CERT_DIR/.haproxy.pem.XXXXXX"
)"

trap 'rm -f "$TEMP_PEM"' EXIT

cat \
  "$LINEAGE/fullchain.pem" \
  "$LINEAGE/privkey.pem" \
  > "$TEMP_PEM"

chmod 600 "$TEMP_PEM"
mv -f "$TEMP_PEM" "$CERT_DIR/haproxy.pem"
TEMP_PEM=""

haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl reload haproxy

if systemctl is-active --quiet stunnel4 2>/dev/null; then
  systemctl reload stunnel4 2>/dev/null ||
    systemctl restart stunnel4
fi
EOFHOOK
} > /etc/letsencrypt/renewal-hooks/deploy/hamada-haproxy-reload.sh

chmod +x /etc/letsencrypt/renewal-hooks/deploy/hamada-haproxy-reload.sh

green "HAProxy proxy routing ready on 80, 443, 8080 and 3128."


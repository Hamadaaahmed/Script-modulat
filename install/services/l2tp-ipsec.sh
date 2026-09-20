#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
  DOMAIN="$(cat /etc/hamada/domain 2>/dev/null || hostname -I | awk '{print $1}')"
fi

mkdir -p /etc/hamada /etc/hamada/l2tp-accounts
mkdir -p /etc/xl2tpd /etc/ppp
mkdir -p /etc/ipsec.d/cacerts /etc/ipsec.d/certs /etc/ipsec.d/private

apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  strongswan strongswan-pki strongswan-starter \
  libcharon-extra-plugins libstrongswan-extra-plugins \
  xl2tpd ppp openssl iptables iproute2

echo "$DOMAIN" > /etc/hamada/domain

PSK_FILE="/etc/hamada/l2tp-ipsec.psk"
if [ ! -s "$PSK_FILE" ]; then
  openssl rand -hex 16 > "$PSK_FILE"
fi
chmod 600 "$PSK_FILE"

if [ ! -s /etc/ipsec.d/private/hamada-net-ca-key.pem ] || [ ! -s /etc/ipsec.d/cacerts/hamada-net-ca-cert.pem ]; then
  rm -f /etc/ipsec.d/private/hamada-net-ca-key.pem /etc/ipsec.d/cacerts/hamada-net-ca-cert.pem
  ipsec pki --gen --type rsa --size 4096 --outform pem > /etc/ipsec.d/private/hamada-net-ca-key.pem
  ipsec pki --self --ca --lifetime 3650 \
    --in /etc/ipsec.d/private/hamada-net-ca-key.pem \
    --type rsa --dn "CN=HAMADA NET VPN CA" \
    --outform pem > /etc/ipsec.d/cacerts/hamada-net-ca-cert.pem
fi

if [ ! -s /etc/ipsec.d/private/hamada-net-server-key.pem ] || [ ! -s /etc/ipsec.d/certs/hamada-net-server-cert.pem ]; then
  rm -f /etc/ipsec.d/private/hamada-net-server-key.pem /etc/ipsec.d/certs/hamada-net-server-cert.pem
  ipsec pki --gen --type rsa --size 4096 --outform pem > /etc/ipsec.d/private/hamada-net-server-key.pem
  ipsec pki --pub --in /etc/ipsec.d/private/hamada-net-server-key.pem --type rsa \
    | ipsec pki --issue --lifetime 1825 \
      --cacert /etc/ipsec.d/cacerts/hamada-net-ca-cert.pem \
      --cakey /etc/ipsec.d/private/hamada-net-ca-key.pem \
      --dn "CN=${DOMAIN}" \
      --san "${DOMAIN}" \
      --flag serverAuth --flag ikeIntermediate \
      --outform pem > /etc/ipsec.d/certs/hamada-net-server-cert.pem
fi

chmod 600 /etc/ipsec.d/private/*.pem || true

# Export the IKEv2 CA certificate through the web root so Android/strongSwan clients
# can import it when the server certificate is self-signed/private-CA based.
mkdir -p /var/www/html
cp -f /etc/ipsec.d/cacerts/hamada-net-ca-cert.pem /var/www/html/hamada-ca.crt
chmod 0644 /var/www/html/hamada-ca.crt

cat > /etc/ipsec.conf <<EOFCONF
config setup
  uniqueids=no
  charondebug="ike 1, knl 1, cfg 0"

conn %default
  keyingtries=3
  dpddelay=30s
  dpdtimeout=120s
  dpdaction=clear
  fragmentation=yes

conn ikev2-mschapv2
  auto=add
  keyexchange=ikev2
  type=tunnel
  forceencaps=yes
  fragmentation=yes
  mobike=yes
  rekey=no
  left=%any
  leftid=@${DOMAIN}
  leftcert=hamada-net-server-cert.pem
  leftsendcert=always
  leftauth=pubkey
  leftsubnet=0.0.0.0/0
  right=%any
  rightid=%any
  rightauth=eap-mschapv2
  rightsourceip=10.21.0.0/24
  rightdns=1.1.1.1,8.8.8.8
  eap_identity=%identity
  ike=aes256-sha256-ecp521,aes256-sha256-ecp384,aes256-sha256-ecp256,aes128-sha256-ecp256,aes256-sha256-modp4096,aes256-sha256-modp3072,aes256-sha256-modp2048,aes128-sha256-modp2048,aes256-sha1-modp2048,aes128-sha1-modp2048,3des-sha1-modp1024!
  esp=aes256-sha256,aes128-sha256,aes256-sha1,aes128-sha1!

conn l2tp-ipsec-psk
  auto=add
  keyexchange=ikev1
  authby=secret
  type=transport
  forceencaps=yes
  left=%any
  leftprotoport=17/1701
  right=%any
  rightprotoport=17/%any
  ike=aes256-sha1-modp1024,3des-sha1-modp1024!
  esp=aes256-sha1,3des-sha1!
EOFCONF

cat > /etc/xl2tpd/xl2tpd.conf <<'EOFXL2TP'
[global]
listen-addr = 0.0.0.0
ipsec saref = no

[lns default]
ip range = 10.20.0.10-10.20.0.250
local ip = 10.20.0.1
require authentication = yes
name = HAMADA-NET-L2TP
ppp debug = no
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOFXL2TP

cat > /etc/ppp/options.xl2tpd <<'EOFPPP'
ipcp-accept-local
ipcp-accept-remote
ms-dns 1.1.1.1
ms-dns 8.8.8.8
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
noccp
auth
mtu 1400
mru 1400
nodefaultroute
proxyarp
lock
hide-password
lcp-echo-interval 30
lcp-echo-failure 4
connect-delay 5000
EOFPPP

touch /etc/ppp/chap-secrets
chmod 600 /etc/ppp/chap-secrets

cat > /etc/sysctl.d/99-hamada-net-l2tp.conf <<'EOFSYS'
net.ipv4.ip_forward=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.default.send_redirects=0
EOFSYS
sysctl --system >/dev/null || true

cat > /usr/local/sbin/hamada-l2tp-firewall <<'EOFFW'
#!/usr/bin/env bash
set -euo pipefail

IFACE="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
IFACE="${IFACE:-eth0}"

sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true

for p in 500 4500 1701; do
  iptables -C INPUT -p udp --dport "$p" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "$p" -j ACCEPT
done

iptables -C FORWARD -s 10.20.0.0/24 -j ACCEPT 2>/dev/null || iptables -A FORWARD -s 10.20.0.0/24 -j ACCEPT
iptables -C FORWARD -d 10.20.0.0/24 -j ACCEPT 2>/dev/null || iptables -A FORWARD -d 10.20.0.0/24 -j ACCEPT
iptables -C FORWARD -s 10.21.0.0/24 -j ACCEPT 2>/dev/null || iptables -A FORWARD -s 10.21.0.0/24 -j ACCEPT
iptables -C FORWARD -d 10.21.0.0/24 -j ACCEPT 2>/dev/null || iptables -A FORWARD -d 10.21.0.0/24 -j ACCEPT

iptables -t nat -C POSTROUTING -s 10.20.0.0/24 -o "$IFACE" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -o "$IFACE" -j MASQUERADE
iptables -t nat -C POSTROUTING -s 10.21.0.0/24 -o "$IFACE" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.21.0.0/24 -o "$IFACE" -j MASQUERADE
EOFFW
chmod 0755 /usr/local/sbin/hamada-l2tp-firewall

cat > /etc/systemd/system/hamada-l2tp-firewall.service <<'EOFSVC'
[Unit]
Description=HAMADA NET L2TP/IPSec firewall rules
After=network-online.target
Wants=network-online.target
Before=strongswan-starter.service xl2tpd.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hamada-l2tp-firewall
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOFSVC

systemctl daemon-reload
systemctl enable --now hamada-l2tp-firewall.service >/dev/null 2>&1 || true

cat > /etc/cron.d/hamada-net-l2tp-expire <<'EOFCRON'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
5 0 * * * root /usr/bin/hn-l2tp-sync >/dev/null 2>&1 || true
EOFCRON

if command -v hn-l2tp-sync >/dev/null 2>&1; then
  hn-l2tp-sync
fi

systemctl enable xl2tpd >/dev/null 2>&1 || true
systemctl restart xl2tpd

systemctl enable strongswan-starter >/dev/null 2>&1 || true
systemctl restart strongswan-starter || ipsec restart || true

sleep 1

if ! systemctl is-active --quiet strongswan-starter; then
  systemctl status strongswan-starter --no-pager || true
  journalctl -u strongswan-starter -n 80 --no-pager || true
  exit 1
fi

if ! systemctl is-active --quiet xl2tpd; then
  systemctl status xl2tpd --no-pager || true
  journalctl -u xl2tpd -n 80 --no-pager || true
  exit 1
fi

echo "[OK] ROUTER protocol configured: L2TP/IPSec PSK."
echo "[OK] ANDROID protocol configured: IKEv2/IPSec MSCHAPv2."
echo "[OK] Android CA certificate: http://${DOMAIN}/hamada-ca.crt"
echo "[OK] Router L2TP PSK: $(cat "$PSK_FILE")"

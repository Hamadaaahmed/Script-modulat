#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${HAMADA_REPO_URL:-https://github.com/Hamadaaahmed/commercial-vps-autoscript.git}"
INSTALL_DIR="${HAMADA_DIR:-/root/commercial-vps-autoscript}"
REF="${HAMADA_REF:-}"

TOKEN="${HAMADA_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}"
REPO_TARBALL_URL="${HAMADA_REPO_TARBALL_URL:-}"

DOMAIN="${1:-}"

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "[INFO] $*"; }

line(){ echo "============================================"; }
title(){
  clear
  line
  echo "        HAMADA NET INSTALLER"
  line
}
section(){
  line
  echo " $1"
  line
}

detect_supported_os() {
  [ -r /etc/os-release ] || die "Cannot detect OS: /etc/os-release not found"

  . /etc/os-release

  local os_id="${ID:-}"
  local version_id="${VERSION_ID:-}"
  local major="${version_id%%.*}"

  case "$os_id:$major" in
    debian:9|debian:10|debian:11|debian:12|debian:13)
      info "Supported OS detected: Debian $version_id"
      ;;
    ubuntu:18|ubuntu:20|ubuntu:22|ubuntu:24|ubuntu:25)
      info "Supported OS detected: Ubuntu $version_id"
      ;;
    *)
      die "Unsupported OS: ${PRETTY_NAME:-$os_id $version_id}. Supported: Debian 9-13, Ubuntu 18-25"
      ;;
  esac
}

clean_domain() {
  printf '%s' "$1" | sed -E 's#^https?://##; s#/.*$##' | tr -d '[:space:]'
}

valid_domain() {
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$'
}

server_ipv4() {
  local ip=""
  if command -v curl >/dev/null 2>&1; then
    ip="$(curl -4fsS --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null || true)"
  fi
  [ -n "$ip" ] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '%s' "$ip"
}

prompt_domain_value() {
  local label="$1"
  local default_value="${2:-}"
  local value=""

  while true; do
    if [ -n "$default_value" ]; then
      read -r -p "$label [$default_value]: " value </dev/tty
      value="${value:-$default_value}"
    else
      read -r -p "$label: " value </dev/tty
    fi

    value="$(clean_domain "$value")"
    if valid_domain "$value"; then
      printf '%s' "$value"
      return 0
    fi

    echo "Invalid domain. Example: vpn.example.com" >/dev/tty
  done
}

choose_domain() {
  local detected_ip default_wg

  mkdir -p /etc/hamada
  detected_ip="$(server_ipv4)"

  if [ "${HAMADA_UPDATE_MODE:-0}" = "1" ] && [ -s /etc/hamada/domain ]; then
    DOMAIN="$(cat /etc/hamada/domain)"
    A_DOMAIN="$(cat /etc/hamada/a-domain 2>/dev/null || printf '%s' "$DOMAIN")"
    SLOWDNS_NS_DOMAIN="$(cat /etc/hamada/slowdns-ns 2>/dev/null || true)"
    WIREGUARD_DOMAIN="$(cat /etc/hamada/wireguard-domain 2>/dev/null || printf '%s' "$DOMAIN")"
  else
    [ -r /dev/tty ] || die "Interactive terminal is required to enter domain settings"

    title
    section "Manual DNS Configuration"
    echo "This installer will NOT create DNS records automatically."
    echo "Create the requested DNS records yourself before continuing."
    [ -n "$detected_ip" ] && echo "Detected server IPv4: $detected_ip"
    line

    if [ -n "${DOMAIN:-}" ]; then
      DOMAIN="$(clean_domain "$DOMAIN")"
      valid_domain "$DOMAIN" || die "Invalid domain: $DOMAIN"
    else
      DOMAIN="$(prompt_domain_value "Main VPN domain")"
    fi

    A_DOMAIN="$(prompt_domain_value "A-record hostname" "$DOMAIN")"
    SLOWDNS_NS_DOMAIN="$(prompt_domain_value "SlowDNS NS hostname")"
    default_wg="wg.${DOMAIN}"
    WIREGUARD_DOMAIN="$(prompt_domain_value "WireGuard domain" "$default_wg")"
  fi

  printf '%s\n' "$DOMAIN" > /etc/hamada/domain
  printf '%s\n' "$A_DOMAIN" > /etc/hamada/a-domain
  printf '%s\n' "$SLOWDNS_NS_DOMAIN" > /etc/hamada/slowdns-ns
  printf '%s\n' "$WIREGUARD_DOMAIN" > /etc/hamada/wireguard-domain
  printf '%s\n' "$detected_ip" > /etc/hamada/server-ip
  chmod 600 /etc/hamada/domain /etc/hamada/a-domain \
    /etc/hamada/slowdns-ns /etc/hamada/wireguard-domain \
    /etc/hamada/server-ip

  export DOMAIN A_DOMAIN SLOWDNS_NS_DOMAIN WIREGUARD_DOMAIN

  line
  echo "DNS values saved:"
  echo "Main domain      : $DOMAIN"
  echo "A-record hostname: $A_DOMAIN"
  echo "SlowDNS NS       : $SLOWDNS_NS_DOMAIN"
  echo "WireGuard domain : $WIREGUARD_DOMAIN"
  [ -n "$detected_ip" ] && echo "Server IPv4      : $detected_ip"
  line
}

if [ "$(id -u)" -ne 0 ]; then
  die "Run as root"
fi

detect_supported_os

if [ -z "$REPO_TARBALL_URL" ] && [ -z "$TOKEN" ] && [ -r /dev/tty ]; then
  read -r -s -p "Enter GitHub token (leave empty for public repo): " TOKEN </dev/tty
  echo >/dev/tty
fi

choose_domain

DOMAIN="$(clean_domain "$DOMAIN")"
valid_domain "$DOMAIN" || die "Invalid domain: $DOMAIN"

export DEBIAN_FRONTEND=noninteractive
export DOMAIN A_DOMAIN SLOWDNS_NS_DOMAIN WIREGUARD_DOMAIN

ASKPASS_DIR=""
cleanup() {
  if [ -n "$ASKPASS_DIR" ]; then
    rm -rf "$ASKPASS_DIR"
  fi
}
trap cleanup EXIT

if [ -n "$TOKEN" ]; then
  ASKPASS_DIR="$(mktemp -d)"
  cat > "$ASKPASS_DIR/git-askpass.sh" <<'ASKPASS'
#!/usr/bin/env sh
case "$1" in
  *Username*|*username*) printf '%s\n' "x-access-token" ;;
  *Password*|*password*) printf '%s\n' "${HAMADA_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}" ;;
  *) printf '\n' ;;
esac
ASKPASS
  chmod 700 "$ASKPASS_DIR/git-askpass.sh"
  export GIT_ASKPASS="$ASKPASS_DIR/git-askpass.sh"
  export GIT_TERMINAL_PROMPT=0
  export HAMADA_GITHUB_TOKEN="$TOKEN"
  export GITHUB_TOKEN="$TOKEN"
fi

echo "============================================"
echo "        HAMADA NET ONE COMMAND INSTALL"
echo "============================================"
echo "Domain : $DOMAIN"
echo "Repo   : $REPO_URL"
echo "Ref    : $REF"
echo "Path   : $INSTALL_DIR"
echo "============================================"

apt-get update -y
apt-get install -y git curl ca-certificates netcat-openbsd dnsutils

if [ "${HAMADA_RESET:-0}" = "1" ] && command -v hamada-reset >/dev/null 2>&1; then
  info "Running HAMADA NET reset..."
  printf 'RESET\n' | hamada-reset || true
  hash -r
fi

if [ -n "$REPO_TARBALL_URL" ]; then
  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  curl -4fsSL "$REPO_TARBALL_URL" | tar -xz --strip-components=1 -C "$INSTALL_DIR"
  cd "$INSTALL_DIR"
else
  if [ -d "$INSTALL_DIR/.git" ]; then
    cd "$INSTALL_DIR"
    git remote set-url origin "$REPO_URL" || true
    git fetch origin --tags
  else
    rm -rf "$INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    git fetch origin --tags
  fi

  if [ -n "$REF" ]; then
    if git rev-parse --verify --quiet "refs/remotes/origin/$REF" >/dev/null; then
      git reset --hard "origin/$REF"
    else
      git reset --hard "$REF"
    fi
  else
    info "HAMADA_REF not set; preserving current checkout."
  fi

  git clean -fdx
  git remote set-url origin "$REPO_URL" || true
fi

bash -n install/install.sh install/services/*.sh scripts/bootstrap-full-install.sh setup.sh
while IFS= read -r file; do
  first_line="$(head -n 1 "$file" 2>/dev/null || true)"
  case "$first_line" in
    *bash*|*"/sh") bash -n "$file" ;;
    *python*) python3 -m py_compile "$file" ;;
  esac
done < <(find usr/bin -maxdepth 1 -type f -print)

# Phase 2.5: deploy and validate the versioned Python Core before installing wrappers.
python3 scripts/hamada-runtime-deploy deploy --source "$INSTALL_DIR" --root /opt/hamada

while IFS= read -r source_file; do
  name="$(basename "$source_file")"
  if [ "$name" = "renew-ssh" ]; then
    install -m 0755 "$source_file" /usr/bin/.renew-ssh.hamada-new
    mv -f /usr/bin/.renew-ssh.hamada-new /usr/bin/renew-ssh
  else
    install -m 0755 "$source_file" "/usr/bin/$name"
  fi
done < <(find usr/bin -maxdepth 1 -type f -print)
command -v hamada-wg-web-fix >/dev/null 2>&1 && hamada-wg-web-fix || true

bash scripts/bootstrap-full-install.sh "$DOMAIN" 2>&1 | tee "/root/hamada-net-install-$DOMAIN.log"

cat > /etc/profile.d/hamada-net-menu.sh <<'PROFILE'
# HAMADA NET auto menu on root interactive login
if [ "$(id -u)" -eq 0 ] && [ -t 1 ] && [ -z "${HAMADA_MENU_SHOWN:-}" ] && [ -z "${SSH_ORIGINAL_COMMAND:-}" ]; then
  if command -v menu >/dev/null 2>&1; then
    export HAMADA_MENU_SHOWN=1
    clear 2>/dev/null || true
    menu || true
  fi
fi
PROFILE
chmod 0644 /etc/profile.d/hamada-net-menu.sh

echo "============================================"
echo "        HAMADA NET DOMAIN"
echo "============================================"
cat /etc/hamada/domain 2>/dev/null || true

echo "============================================"
echo "        HAMADA NET SERVICES STATUS"
echo "============================================"
HAMADA_STATUS_NO_PAUSE=1 hn-status || true

echo "============================================"
echo "        HAMADA NET DOCTOR CHECK"
echo "============================================"
hamada-doctor || true

echo "============================================"
echo "        HAMADA NET SYSTEMD SERVICES"
echo "============================================"
for svc in \
  ssh \
  sshd \
  dropbear \
  nginx \
  haproxy \
  stunnel4 \
  squid \
  openvpn-server@server-tcp-1194 \
  openvpn-server@server-udp-2200 \
  hamada-openvpn-ws \
  strongswan-starter \
  xl2tpd \
  hamada-l2tp-firewall \
  wg-quick@wg0 \
  zivpn \
  hamada-zivpn-firewall
do
  if systemctl status "$svc" >/dev/null 2>&1; then
    printf '%-36s : ' "$svc"
    systemctl is-active "$svc" 2>/dev/null || true
  fi
done

echo "============================================"
echo "        HAMADA NET LISTENING PORTS"
echo "============================================"
ss -tulpn | grep -E ':(22|80|443|444|777|109|143|3128|8080|10080|10081|10082|1194|2200|500|4500|1701|51820|5667)([[:space:]]|$)' || true

mkdir -p /etc/hamada
if git rev-parse HEAD >/dev/null 2>&1; then
  git rev-parse HEAD > /etc/hamada/version.sha
elif [ -n "${HAMADA_VERSION:-}" ]; then
  printf "%s\n" "$HAMADA_VERSION" > /etc/hamada/version.sha
fi

echo "============================================"
echo "        HAMADA NET INSTALL COMPLETED"
echo "============================================"
echo "Server will reboot after 15 seconds..."
echo "After reboot, SSH login will open HAMADA NET menu automatically."
echo "Press CTRL+C now only if you want to cancel reboot."

for i in $(seq 15 -1 1); do
  printf '\rReboot in %02d seconds...' "$i"
  sleep 1
done
echo

if [ "${HAMADA_NO_REBOOT:-0}" = "1" ]; then
  echo "Reboot skipped because HAMADA_NO_REBOOT=1"
else
  systemctl reboot
fi


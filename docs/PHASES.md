# Rebuild phases

## Phase 0
Safe reset / uninstall command.

## Phase 1A
SSH/OpenVPN base:
- OpenSSH Direct 22
- Dropbear Direct 109/143
- Nginx MultiPort 80/443
- SSH WebSocket /ssh
- SSH WebSocket TLS /ssh
- OpenVPN TCP 1194
- OpenVPN UDP 2200
- OpenVPN WebSocket /openvpn
- Squid Proxy 3128/8080
- HAProxy 443 multiplexer
- SSH TLS Direct 443
- Stunnel alternate TLS 444/777

## Next
- BadVPN UDPGW
- SSH UDP Custom
- SlowDNS
- V2Ray on 443 paths

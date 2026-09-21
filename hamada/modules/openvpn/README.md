# OpenVPN Core Reference Module

Phase 3A introduces a read-only OpenVPN runtime model and inspection layer.

## Observed legacy contract

- TCP OpenVPN: port 1194, `tcp4`, network `10.8.0.0/24`.
- UDP OpenVPN: port 2200, `udp4`, network `10.9.0.0/24`.
- Authentication: OpenVPN PAM plugin with Linux accounts.
- WebSocket bridge: `127.0.0.1:10082` to TCP OpenVPN `127.0.0.1:1194`.
- Client profiles remain under `/var/www/html/vpn-files`.
- Existing systemd units remain legacy-owned.
- NAT/forwarding remains legacy/shared infrastructure.

## Ownership boundary

OpenVPN Core does not own Linux account creation, renewal or deletion. PAM
consumes the existing Linux-account backend.

Phase 3A also does not own or mutate:

- iptables/firewall/NAT
- Nginx or HAProxy
- systemd unit installation
- OpenVPN PKI generation
- OpenVPN server configuration
- WebSocket bridge configuration
- public `/usr/bin` commands
- `/opt/hamada` runtime cutover

The module parses OpenVPN configuration as data and performs read-only system
inspection. It never sources shell files and exposes no start/stop/restart or
configuration-writing API.

Mutation and runtime cutover are explicitly deferred to a later Phase 3 step
after characterization and regression coverage.

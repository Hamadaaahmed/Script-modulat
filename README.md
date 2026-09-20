# commercial-vps-autoscript

Manual-DNS build.

## Installation inputs

The installer asks for:

- Main VPN domain
- A-record hostname
- SlowDNS NS hostname
- WireGuard domain

The installer does not create DNS records automatically. Create the required A and NS
records before requesting a public TLS certificate.

Saved values:

- `/etc/hamada/domain`
- `/etc/hamada/a-domain`
- `/etc/hamada/slowdns-ns`
- `/etc/hamada/wireguard-domain`
- `/etc/hamada/server-ip`

The WireGuard hostname must resolve directly to the VPS public IPv4. Do not place it
behind an HTTP/CDN proxy because WireGuard uses UDP port 51820.

## Update source

Updates are downloaded from the configured GitHub repository.

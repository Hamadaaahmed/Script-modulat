# SSH Core Reference Architecture

## Owns in source
- Account-domain API and deterministic expiration calculations.
- Safe legacy metadata parsing and atomic 0600 writes.
- Linux account system adapter using argument arrays and no `shell=True`.
- Read-only OpenSSH health primitives.
- Compatibility helper API for future staged command cutover.

## Does not own in runtime in Phase 2
All existing public SSH commands and installer behavior remain legacy. Dropbear, Stunnel, WebSocket bridges, OpenVPN, SlowDNS, UDP Custom, Edge, Firewall, Xray, certificates, and global systemd ownership remain outside SSH Core.

## Why no public-command cutover yet
The source package has no established runtime installation location for the new `hamada` Python package. Switching `/usr/bin` scripts would therefore require changing bootstrap/update deployment semantics or embedding duplicated core code. Both are broader than a safe reference-module step. Phase 2 stops at a tested reference-ready core and documents the cutover adapter instead of creating a fragile dependency.

## Rollback
No public command cutover occurs in this phase, so rollback is filesystem-level: remove/revert the Phase 2 `hamada/modules/ssh`, SSH docs/tests, and restore the Phase 1 schema/SSH manifest. Existing runtime scripts remain the fallback because they were not changed.

## Security
New metadata code never uses `source` or `eval`; it rejects unsafe metadata syntax, writes atomically with mode 0600, and never logs credentials. Password storage itself remains for compatibility and is not redesigned here.

# SSH Core Reference Module

Phase 2 owns the **SSH account domain** and safe legacy metadata handling. It does not own Dropbear, Stunnel, WebSocket bridges, OpenVPN, SlowDNS, UDP Custom, HAProxy/Nginx, or firewall rules.

The existing backend remains Linux users plus `/etc/hamada/ssh-accounts`. No account database or migration is introduced.

Selective cutover: `renew-ssh` and `del-ssh` use the new SSH Core while preserving their interactive presentation. `add-ssh`, `trial-ssh`, `cek-ssh`, `show-ssh`, and `menu-ssh` remain legacy because they contain mixed presentation/payload/session behavior. Legacy copies of migrated commands are retained under `usr/lib/hamada/legacy/ssh/` for explicit rollback.

Metadata is parsed as data, never sourced or evaluated. New writes are atomic and mode 0600. Passwords remain in legacy metadata for compatibility; redesign is deferred.

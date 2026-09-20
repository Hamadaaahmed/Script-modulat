# Runtime Bug Backlog — recorded only, not fixed in Phase 1

| ID | Severity | Component | Current behavior | Expected behavior | Risk | Suggested future phase |
|---|---|---|---|---|---|---|
| HN-001 | High | UDP Custom/Xray | UDP Custom catch-all can capture Xray mKCP UDP 443 | Explicit non-overlapping ownership | VLESS mKCP failure | Firewall/Protocol migration |
| HN-002 | High | UDP Custom/Xray | UDP 8459 can be captured from VMess mKCP | Explicit non-overlapping ownership | VMess mKCP failure | Firewall/Protocol migration |
| HN-003 | High | Xray/Edge | vless-xhttp-reality routing does not align with its backend port | Correct declared route/backend | Preset unavailable | Xray/Edge migration |
| HN-004 | High | Xray | --listen-port is stored but grouped inbound uses preset base | Stored port matches runtime listener semantics | State/runtime mismatch | Xray migration |
| HN-005 | High | Xray Shadowsocks | Grouped preset uses first active password | Account behavior is explicit/correct | Multi-account failure | Xray migration |
| HN-006 | High | WG/ZiVPN/Xray | Expiration depends on later sync/build activity | Scheduled reconciliation | Expired access may persist | Account lifecycle phase |
| HN-007 | High | Installer | HAMADA_NO_REBOOT is not propagated to inner reboot scheduling | No reboot when requested | Remote outage | Installer safety phase |
| HN-008 | Medium/High | SlowDNS | Setup input and runtime state files differ | One documented source of truth | Misconfiguration | SlowDNS migration |
| HN-009 | Critical | WireGuard | Client config containing PrivateKey can reside under public web root | Secret delivery/storage is protected | Credential disclosure | Security/WG phase |
| HN-010 | High | Nginx | Multiple scripts can write shared config | Single future edge owner | Config drift | Edge migration |
| HN-011 | High | Firewall | Multiple services own iptables/NAT independently | Central future ownership | Rule/order conflicts | Firewall migration |
| HN-012 | High | Reset/Uninstall | Coverage does not fully match current services | Complete lifecycle inventory | Runtime leftovers | Lifecycle phase |
| HN-013 | High | Config parsing | Some root workflows source .conf data as shell | Safe data parsing | Command execution risk | Security foundation follow-up |
| HN-014 | Critical | Supply chain | Some upstream artifacts/installers lack pin/checksum verification | Pinned verified artifacts | Supply-chain compromise | Release/security phase |
| HN-015 | Medium | Doctor/Status | Coverage is incomplete versus shipped services | Registry-driven complete health view | False healthy status | Health integration phase |

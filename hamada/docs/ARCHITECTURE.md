# HAMADA NET VIP VPN MANAGER — Enterprise Foundation

## Phase 1 boundary
Phase 1 adds a read-only architectural foundation beside the legacy runtime. Legacy installation, services, ports, firewall, configs, certificates, account stores, updater, menus and public commands remain the runtime source of truth. Nothing in `hamada/` is installed or invoked by the legacy flow.

## Foundation
`core/paths.py` names future and legacy path roots without changing them. `core/registry.py` loads declarative JSON manifests and builds module/dependency/conflict/port views. `core/validation.py` validates manifests and cross-module contracts without executing manifest content. `core/health.py` is deliberately read-only. `core/output.py` defines quiet, deterministic INFO/OK/WARN/ERROR/DEBUG output.

## Ownership model
A future module declares what it needs; it does not directly own shared infrastructure. Firewall declarations are requirements only until a future central firewall controller exists. Edge routes/backends are declarations only until a future edge controller exists. Phase 1 applies neither.

## Migration strategy
Use strangler migration: foundation first, then one explicitly approved reference module, compatibility wrappers retained, tests before/after, and no legacy removal until separately approved. Phase 2 is not part of this change.

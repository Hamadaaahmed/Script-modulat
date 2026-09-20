# Health and testing model
Health is read-only by contract: inspect files, binaries, config validity, systemd unit existence/state, ports, certificates and dependencies. No restart, auto-fix, config write or firewall write is permitted in this foundation.

Tests use Python standard-library `unittest`; production VPS access is unnecessary. Contract tests cover manifests, registries, duplicate IDs/ports, protocol namespace separation, dependencies/cycles, conflicts, paths and output behavior. Future integration tests belong in later approved phases.

# Registries and ownership

## Module registry
Loads `manifests/*.json` deterministically. It can answer module identity, dependencies, services, requirements, ports, account capability and planned health checks. It performs no runtime mutation.

## Port registry
TCP and UDP are separate namespaces. Public/internal use of the same protocol+port by different modules is reported. Same numeric TCP and UDP port is allowed. Phase 1 reports conflicts; it never resolves them or changes ports.

## Dependency/conflict registry
Required module references must exist and be acyclic. Optional references are warnings when absent. Infrastructure dependencies are declarative strings in Phase 1. Explicit module conflicts are reportable facts, not auto-remediation.

## Firewall ownership
Legacy firewall remains authoritative. Future manifests declare requirements and ownership metadata only. A future controller may render rules after a separately approved migration.

## Edge ownership
Legacy HAProxy/Nginx remain authoritative. Future route/backend/TLS declarations are data only. Modules should eventually stop writing shared edge configs directly, but Phase 1 makes no such runtime change.

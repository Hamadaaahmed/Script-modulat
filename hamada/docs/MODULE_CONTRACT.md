# Module Contract v1
A module has a stable `id`, human name/version/description, dependencies, conflicts, requirements, paths, services, four port namespaces, firewall requirements, edge declarations, account capabilities, health checks and supported lifecycle operations.

Lifecycle vocabulary: `preflight install configure validate enable start verify reconcile migrate uninstall`. A module declares only operations it supports.

Account interface vocabulary: `account_create account_delete account_renew account_expire account_list account_status account_reconcile`. Unified interface never implies unified storage; Linux users, Xray JSON, WireGuard peers, L2TP/ZiVPN files and upstream databases may remain native backends.

Manifests are data, never executable code. Consumers must not `eval`, shell-source, or execute manifest fields. Paths must be absolute and traversal-free. Secrets must not be logged.

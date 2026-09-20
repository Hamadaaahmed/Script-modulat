# Path policy
Future named roots: `HAMADA_HOME=/opt/hamada`, `CONFIG_ROOT=/etc/hamada`, `STATE_ROOT=/var/lib/hamada`, `MODULE_ROOT=$HAMADA_HOME/modules`, `CERT_ROOT=/etc/letsencrypt`, `BACKUP_ROOT=/var/backups/hamada`, `LOG_ROOT=/var/log/hamada`.

These are definitions, not migrations. Legacy `/usr/bin`, `/etc/hamada`, `/var/www/html`, service-specific config paths and certificate locations remain authoritative in Phase 1. Environment overrides exist for isolated tests/development only and are not wired into legacy runtime.

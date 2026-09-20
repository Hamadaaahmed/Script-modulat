"""Central path definitions. Phase 1 does not alter any runtime path."""
from pathlib import Path
import os

HAMADA_HOME = Path(os.environ.get("HAMADA_HOME", "/opt/hamada"))
CONFIG_ROOT = Path(os.environ.get("HAMADA_CONFIG_ROOT", "/etc/hamada"))
STATE_ROOT = Path(os.environ.get("HAMADA_STATE_ROOT", "/var/lib/hamada"))
MODULE_ROOT = HAMADA_HOME / "modules"
CERT_ROOT = Path(os.environ.get("HAMADA_CERT_ROOT", "/etc/letsencrypt"))
BACKUP_ROOT = Path(os.environ.get("HAMADA_BACKUP_ROOT", "/var/backups/hamada"))
LOG_ROOT = Path(os.environ.get("HAMADA_LOG_ROOT", "/var/log/hamada"))
LEGACY_BIN_ROOT = Path("/usr/bin")
LEGACY_WEB_ROOT = Path("/var/www/html")

NAMED_PATHS = {
    "HAMADA_HOME": HAMADA_HOME, "CONFIG_ROOT": CONFIG_ROOT,
    "STATE_ROOT": STATE_ROOT, "MODULE_ROOT": MODULE_ROOT,
    "CERT_ROOT": CERT_ROOT, "BACKUP_ROOT": BACKUP_ROOT,
    "LOG_ROOT": LOG_ROOT, "LEGACY_BIN_ROOT": LEGACY_BIN_ROOT,
    "LEGACY_WEB_ROOT": LEGACY_WEB_ROOT,
}

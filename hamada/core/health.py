"""Read-only health foundation. It never fixes, restarts, writes configs or firewall."""
from dataclasses import dataclass
from pathlib import Path
import shutil

@dataclass(frozen=True)
class HealthResult:
    check: str; status: str; detail: str

class HealthEngine:
    def file_exists(self,path):
        ok=Path(path).exists(); return HealthResult("file_exists","OK" if ok else "FAIL",str(path))
    def binary_exists(self,binary):
        found=shutil.which(binary); return HealthResult("binary_exists","OK" if found else "FAIL",found or binary)
    def planned_checks(self,manifest):
        return tuple(manifest.get("healthchecks",[]))

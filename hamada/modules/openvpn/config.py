"""Safe, non-executing parser for the legacy OpenVPN server configuration."""
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple, Union

from .errors import OpenVPNConfigError


class OpenVPNConfig:
    def __init__(self, directives: Dict[str, List[Tuple[str, ...]]]) -> None:
        self.directives = directives

    def values(self, name: str) -> Tuple[Tuple[str, ...], ...]:
        return tuple(self.directives.get(name, ()))

    def first(self, name: str) -> Optional[Tuple[str, ...]]:
        values = self.values(name)
        return values[0] if values else None

    def scalar(self, name: str, default: Optional[str] = None) -> Optional[str]:
        value = self.first(name)
        if not value:
            return default
        return value[0]

    def has(self, name: str) -> bool:
        return name in self.directives


class OpenVPNConfigParser:
    """Parse directives as data.

    No shell sourcing, interpolation, include execution or command execution
    is performed.
    """

    @staticmethod
    def parse_text(text: str) -> OpenVPNConfig:
        directives = {}  # type: Dict[str, List[Tuple[str, ...]]]

        for number, original in enumerate(text.splitlines(), 1):
            line = original.strip()
            if not line or line.startswith("#") or line.startswith(";"):
                continue

            parts = line.split()
            if not parts:
                continue

            name = parts[0]
            if not name or any(ch.isspace() for ch in name):
                raise OpenVPNConfigError(
                    "invalid directive name on line {}".format(number)
                )

            directives.setdefault(name, []).append(tuple(parts[1:]))

        return OpenVPNConfig(directives)

    @classmethod
    def parse_file(cls, path: Union[str, Path]) -> OpenVPNConfig:
        target = Path(path)
        try:
            text = target.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            raise OpenVPNConfigError(
                "cannot read OpenVPN config: {}".format(target)
            ) from exc
        return cls.parse_text(text)


def validate_server_config(
    config: OpenVPNConfig,
    *,
    port: int,
    proto: str,
    network: str,
    netmask: str,
) -> Tuple[str, ...]:
    """Return validation findings without changing the system."""
    findings = []  # type: List[str]

    expected = {
        "port": (str(port),),
        "proto": (proto,),
        "dev": ("tun",),
        "server": (network, netmask),
        "verify-client-cert": ("none",),
    }

    for directive, value in expected.items():
        if config.first(directive) != value:
            findings.append(
                "{} expected {!r}, found {!r}".format(
                    directive, value, config.first(directive)
                )
            )

    if not config.has("username-as-common-name"):
        findings.append("username-as-common-name missing")

    plugin = config.first("plugin")
    if not plugin or len(plugin) < 2 or plugin[-1] != "login":
        findings.append("PAM authentication plugin/login missing")

    for directive in ("ca", "cert", "key", "dh"):
        value = config.first(directive)
        if not value or len(value) != 1:
            findings.append("{} path missing".format(directive))

    return tuple(findings)

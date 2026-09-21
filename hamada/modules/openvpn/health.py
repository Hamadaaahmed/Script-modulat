"""Read-only OpenVPN health inspection."""
from typing import Tuple

from .config import OpenVPNConfigParser, validate_server_config
from .model import OpenVPNContract
from .system import OpenVPNSystem


class OpenVPNHealthItem:
    def __init__(self, name: str, ok: bool, detail: str) -> None:
        self.name = name
        self.ok = ok
        self.detail = detail


class OpenVPNHealthService:
    def __init__(self, system=None, contract=None, parser=None) -> None:
        self.system = system or OpenVPNSystem()
        self.contract = contract or OpenVPNContract()
        self.parser = parser or OpenVPNConfigParser()

    def inspect(self) -> Tuple[OpenVPNHealthItem, ...]:
        items = []

        binary = self.system.binary_path("openvpn")
        items.append(
            OpenVPNHealthItem(
                "openvpn_binary",
                bool(binary),
                binary or "missing",
            )
        )

        for path in self.contract.required_files:
            items.append(
                OpenVPNHealthItem(
                    "file:{}".format(path),
                    self.system.file_exists(path),
                    path,
                )
            )

        for profile in self.contract.client_profiles:
            items.append(
                OpenVPNHealthItem(
                    "profile:{}".format(profile),
                    self.system.file_exists(profile),
                    profile,
                )
            )

        plugin = self.system.pam_plugin()
        items.append(
            OpenVPNHealthItem(
                "pam_plugin",
                bool(plugin),
                plugin or "missing",
            )
        )

        for service in self.contract.services:
            items.append(
                OpenVPNHealthItem(
                    "service_active:{}".format(service),
                    self.system.service_active(service),
                    service,
                )
            )

        items.extend(self._config_checks())

        items.append(
            OpenVPNHealthItem(
                "listener:tcp:1194",
                self.system.tcp_listener_present("0.0.0.0", 1194),
                "TCP 1194",
            )
        )
        items.append(
            OpenVPNHealthItem(
                "listener:udp:2200",
                self.system.udp_listener_present("0.0.0.0", 2200),
                "UDP 2200",
            )
        )
        items.append(
            OpenVPNHealthItem(
                "listener:tcp:127.0.0.1:10082",
                self.system.tcp_listener_present("127.0.0.1", 10082),
                "127.0.0.1:10082",
            )
        )

        return tuple(items)

    def _config_checks(self):
        items = []

        definitions = (
            (
                "tcp_config",
                self.contract.tcp_config,
                self.contract.tcp_port,
                "tcp4",
                self.contract.tcp_network,
                self.contract.tcp_netmask,
            ),
            (
                "udp_config",
                self.contract.udp_config,
                self.contract.udp_port,
                "udp4",
                self.contract.udp_network,
                self.contract.udp_netmask,
            ),
        )

        for name, path, port, proto, network, netmask in definitions:
            if not self.system.file_exists(path):
                items.append(
                    OpenVPNHealthItem(name, False, "{} missing".format(path))
                )
                continue

            try:
                config = self.parser.parse_file(path)
                findings = validate_server_config(
                    config,
                    port=port,
                    proto=proto,
                    network=network,
                    netmask=netmask,
                )
            except Exception as exc:
                items.append(
                    OpenVPNHealthItem(name, False, str(exc))
                )
                continue

            items.append(
                OpenVPNHealthItem(
                    name,
                    not findings,
                    "OK" if not findings else "; ".join(findings),
                )
            )

        return items

"""Observed OpenVPN runtime contract.

Phase 3A is descriptive and read-only. These values capture the verified
legacy deployment; they do not configure or mutate the host.
"""
from typing import Tuple


class OpenVPNContract:
    tcp_config: str = "/etc/openvpn/server/server-tcp-1194.conf"
    udp_config: str = "/etc/openvpn/server/server-udp-2200.conf"

    tcp_service: str = "openvpn-server@server-tcp-1194.service"
    udp_service: str = "openvpn-server@server-udp-2200.service"
    websocket_service: str = "hamada-openvpn-ws.service"

    tcp_port: int = 1194
    udp_port: int = 2200

    websocket_host: str = "127.0.0.1"
    websocket_port: int = 10082
    websocket_target_host: str = "127.0.0.1"
    websocket_target_port: int = 1194

    tcp_network: str = "10.8.0.0"
    tcp_netmask: str = "255.255.255.0"
    udp_network: str = "10.9.0.0"
    udp_netmask: str = "255.255.255.0"

    ca_path: str = "/etc/openvpn/server/ca.crt"
    cert_path: str = "/etc/openvpn/server/server.crt"
    key_path: str = "/etc/openvpn/server/server.key"
    dh_path: str = "/etc/openvpn/server/dh.pem"

    profile_root: str = "/var/www/html/vpn-files"

    @property
    def services(self) -> Tuple[str, ...]:
        return (
            self.tcp_service,
            self.udp_service,
            self.websocket_service,
        )

    @property
    def required_files(self) -> Tuple[str, ...]:
        return (
            self.tcp_config,
            self.udp_config,
            self.ca_path,
            self.cert_path,
            self.key_path,
            self.dh_path,
        )

    @property
    def client_profiles(self) -> Tuple[str, ...]:
        root = self.profile_root.rstrip("/")
        return (
            root + "/client-tcp-1194.ovpn",
            root + "/client-udp-2200.ovpn",
            root + "/ws 443.ovpn",
            root + "/ws 80.ovpn",
        )

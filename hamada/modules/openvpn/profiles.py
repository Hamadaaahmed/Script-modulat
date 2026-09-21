"""Pure OpenVPN client profile rendering.

Phase 3D owns profile rendering policy only.  This module deliberately
does not write files, manage services, generate PKI, or mutate the host.
"""


class OpenVPNProfileRenderer:
    TCP_PORT = 1194
    UDP_PORT = 2200
    WEBSOCKET_PORTS = (443, 80)

    def __init__(self, domain, ca_certificate):
        self.domain = self._validate_domain(domain)
        self.ca_certificate = self._validate_ca(ca_certificate)

    @staticmethod
    def _validate_domain(domain):
        if not isinstance(domain, str):
            raise ValueError("domain must be a non-empty string")

        value = domain.strip()

        if not value:
            raise ValueError("domain must be a non-empty string")

        if any(character.isspace() for character in value):
            raise ValueError("domain must not contain whitespace")

        return value

    @staticmethod
    def _validate_ca(ca_certificate):
        if not isinstance(ca_certificate, str):
            raise ValueError("CA certificate must be a non-empty string")

        value = ca_certificate.strip()

        if not value:
            raise ValueError("CA certificate must be a non-empty string")

        return value

    def _render(self, proto, port):
        return (
            "client\n"
            "dev tun\n"
            "proto {proto}\n"
            "remote {domain} {port}\n"
            "resolv-retry infinite\n"
            "nobind\n"
            "persist-key\n"
            "persist-tun\n"
            "auth-user-pass\n"
            "remote-cert-tls server\n"
            "verb 3\n"
            "<ca>\n"
            "{ca}\n"
            "</ca>\n"
        ).format(
            proto=proto,
            domain=self.domain,
            port=port,
            ca=self.ca_certificate,
        )

    def tcp(self):
        return self._render("tcp-client", self.TCP_PORT)

    def udp(self):
        return self._render("udp", self.UDP_PORT)

    def websocket(self, port):
        if port not in self.WEBSOCKET_PORTS:
            raise ValueError(
                "unsupported OpenVPN WebSocket port: {}".format(port)
            )

        return self._render("tcp-client", port)

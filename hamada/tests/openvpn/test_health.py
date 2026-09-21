import unittest

from hamada.modules.openvpn.config import OpenVPNConfigParser
from hamada.modules.openvpn.health import OpenVPNHealthService
from hamada.modules.openvpn.model import OpenVPNContract


TCP = """\
port 1194
proto tcp4
dev tun
ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key /etc/openvpn/server/server.key
dh /etc/openvpn/server/dh.pem
server 10.8.0.0 255.255.255.0
plugin /usr/lib/openvpn/openvpn-plugin-auth-pam.so login
verify-client-cert none
username-as-common-name
"""

UDP = TCP.replace("1194", "2200").replace(
    "tcp4", "udp4"
).replace(
    "10.8.0.0", "10.9.0.0"
)


class FakeParser:
    @staticmethod
    def parse_file(path):
        if "tcp" in str(path):
            return OpenVPNConfigParser.parse_text(TCP)
        return OpenVPNConfigParser.parse_text(UDP)


class FakeSystem:
    def binary_path(self, name):
        return "/usr/sbin/openvpn" if name == "openvpn" else None

    def file_exists(self, path):
        return True

    def pam_plugin(self):
        return (
            "/usr/lib/x86_64-linux-gnu/openvpn/plugins/"
            "openvpn-plugin-auth-pam.so"
        )

    def service_active(self, service):
        return True

    def tcp_listener_present(self, host, port):
        return port in (1194, 10082)

    def udp_listener_present(self, host, port):
        return port == 2200


class OpenVPNHealthTests(unittest.TestCase):
    def test_healthy_observed_contract(self):
        service = OpenVPNHealthService(
            system=FakeSystem(),
            contract=OpenVPNContract(),
            parser=FakeParser(),
        )
        results = service.inspect()
        self.assertTrue(results)
        self.assertTrue(all(item.ok for item in results))

    def test_health_is_descriptive(self):
        service = OpenVPNHealthService(
            system=FakeSystem(),
            contract=OpenVPNContract(),
            parser=FakeParser(),
        )
        names = {item.name for item in service.inspect()}
        self.assertIn("tcp_config", names)
        self.assertIn("udp_config", names)
        self.assertIn("listener:tcp:1194", names)
        self.assertIn("listener:udp:2200", names)
        self.assertIn("listener:tcp:127.0.0.1:10082", names)


if __name__ == "__main__":
    unittest.main()

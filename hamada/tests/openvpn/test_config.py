import tempfile
import unittest
from pathlib import Path

from hamada.modules.openvpn.config import (
    OpenVPNConfigParser,
    validate_server_config,
)
from hamada.modules.openvpn.errors import OpenVPNConfigError


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


class OpenVPNConfigTests(unittest.TestCase):
    def test_parse_observed_tcp_contract(self):
        config = OpenVPNConfigParser.parse_text(TCP)
        self.assertEqual(config.first("port"), ("1194",))
        self.assertEqual(config.first("proto"), ("tcp4",))
        self.assertEqual(
            config.first("server"),
            ("10.8.0.0", "255.255.255.0"),
        )
        self.assertTrue(config.has("username-as-common-name"))

    def test_comments_and_repeated_directives_are_data(self):
        config = OpenVPNConfigParser.parse_text(
            "# comment\npush route-a\n; comment\npush route-b\n"
        )
        self.assertEqual(
            config.values("push"),
            (("route-a",), ("route-b",)),
        )

    def test_parser_does_not_execute_shell_syntax(self):
        config = OpenVPNConfigParser.parse_text(
            "setenv TEST $(touch /tmp/hamada-openvpn-should-not-exist)\n"
        )
        self.assertEqual(config.scalar("setenv"), "TEST")

    def test_parse_file_missing_is_config_error(self):
        with self.assertRaises(OpenVPNConfigError):
            OpenVPNConfigParser.parse_file("/definitely/missing/openvpn.conf")

    def test_valid_server_contract_has_no_findings(self):
        config = OpenVPNConfigParser.parse_text(TCP)
        findings = validate_server_config(
            config,
            port=1194,
            proto="tcp4",
            network="10.8.0.0",
            netmask="255.255.255.0",
        )
        self.assertEqual(findings, ())

    def test_contract_drift_is_reported(self):
        config = OpenVPNConfigParser.parse_text(
            TCP.replace("port 1194", "port 443")
        )
        findings = validate_server_config(
            config,
            port=1194,
            proto="tcp4",
            network="10.8.0.0",
            netmask="255.255.255.0",
        )
        self.assertTrue(any("port expected" in item for item in findings))


if __name__ == "__main__":
    unittest.main()

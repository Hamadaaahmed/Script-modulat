import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MAIN_INSTALLER = ROOT / "install" / "install.sh"
SSH_INSTALLER = ROOT / "install" / "modules" / "ssh" / "install.sh"
WS_CLIENT_GENERATOR = ROOT / "install" / "services" / "ovpn-ws-client-files.sh"
MANIFEST = ROOT / "hamada" / "manifests" / "openvpn.json"


class OpenVPNLegacyCharacterizationTests(unittest.TestCase):
    """Capture the observed OpenVPN contract before Phase 3 migration."""

    def read(self, path):
        return path.read_text(encoding="utf-8")

    def assert_contains_all(self, text, values):
        for value in values:
            self.assertIn(value, text)

    def test_main_installer_tcp_contract(self):
        source = self.read(MAIN_INSTALLER)
        self.assert_contains_all(
            source,
            [
                "port 1194",
                "proto tcp4",
                "dev tun",
                "server 10.8.0.0 255.255.255.0",
                "plugin $plugin login",
                "verify-client-cert none",
                "username-as-common-name",
                "status /etc/openvpn/server/openvpn-tcp.log",
                "openvpn-server@server-tcp-1194.service",
            ],
        )

    def test_main_installer_udp_contract(self):
        source = self.read(MAIN_INSTALLER)
        self.assert_contains_all(
            source,
            [
                "port 2200",
                "proto udp4",
                "dev tun",
                "server 10.9.0.0 255.255.255.0",
                "plugin $plugin login",
                "verify-client-cert none",
                "username-as-common-name",
                "status /etc/openvpn/server/openvpn-udp.log",
                "openvpn-server@server-udp-2200.service",
            ],
        )

    def test_pki_and_pam_contract(self):
        source = self.read(MAIN_INSTALLER)
        self.assert_contains_all(
            source,
            [
                'EASYRSA_REQ_CN="HAMADA-CA"',
                "./easyrsa build-ca nopass",
                "./easyrsa gen-dh",
                "./easyrsa build-server-full server nopass",
                "/etc/openvpn/server/ca.crt",
                "/etc/openvpn/server/server.crt",
                "/etc/openvpn/server/server.key",
                "/etc/openvpn/server/dh.pem",
                "openvpn-plugin-auth-pam.so",
            ],
        )

    def test_legacy_nat_contract(self):
        source = self.read(MAIN_INSTALLER)
        self.assert_contains_all(
            source,
            [
                "net.ipv4.ip_forward=1",
                "for NET in 10.8.0.0/24 10.9.0.0/24; do",
                'iptables -t nat -C POSTROUTING',
                'iptables -t nat -A POSTROUTING',
                '-s "$NET" -o "$IFACE" -j MASQUERADE',
                "/usr/local/sbin/hamada-openvpn-firewall",
                "hamada-openvpn-firewall.service",
                "RemainAfterExit=yes",
                "systemctl enable --now hamada-openvpn-firewall.service",
            ],
        )

    def test_client_profile_contract(self):
        source = self.read(MAIN_INSTALLER)
        self.assert_contains_all(
            source,
            [
                "/var/www/html/vpn-files/client-tcp-1194.ovpn",
                "remote $DOMAIN 1194",
                "proto tcp-client",
                "/var/www/html/vpn-files/client-udp-2200.ovpn",
                "remote $DOMAIN 2200",
                "proto udp",
                "auth-user-pass",
                "remote-cert-tls server",
                "<ca>",
                "</ca>",
            ],
        )

    def test_websocket_bridge_contract(self):
        source = self.read(SSH_INSTALLER)
        self.assert_contains_all(
            source,
            [
                "hamada-openvpn-ws.service",
                "After=network.target openvpn-server@server-tcp-1194.service",
                "127.0.0.1 10082 127.0.0.1 1194",
            ],
        )

    def test_websocket_route_and_payload_contract(self):
        main = self.read(MAIN_INSTALLER)
        self.assert_contains_all(
            main,
            [
                "location ~ ^/(openvpn|ovpn|vpn)$",
                "Path    : /openvpn",
                "GET /openvpn HTTP/1.1[crlf]",
            ],
        )

    def test_websocket_profile_generator_contract(self):
        source = self.read(WS_CLIENT_GENERATOR)
        self.assert_contains_all(
            source,
            [
                'BASE="$DIR/client-tcp-1194.ovpn"',
                'remote ${DOMAIN} 443',
                '"$DIR/ws 443.ovpn"',
                'remote ${DOMAIN} 80',
                '"$DIR/ws 80.ovpn"',
                'rm -f "$DIR/openvpn-ws-443.txt"',
            ],
        )

    def test_ssh_module_contains_duplicate_openvpn_configuration(self):
        source = self.read(SSH_INSTALLER)
        self.assert_contains_all(
            source,
            [
                "configure_openvpn()",
                "port 1194",
                "server 10.8.0.0 255.255.255.0",
                "port 2200",
                "server 10.9.0.0 255.255.255.0",
                "/var/www/html/vpn-files/client-tcp-1194.ovpn",
                "/var/www/html/vpn-files/client-udp-2200.ovpn",
            ],
        )

    def test_udp_custom_preserves_openvpn_udp_port(self):
        source = self.read(
            ROOT / "install" / "modules" / "ssh" / "services" / "udp-custom.sh"
        )
        self.assertIn("2200", source)
        self.assertIn(
            "53,68,500,1701,2200,4500,5667,6000-19999,10994,36712,51820",
            source,
        )

    def test_manifest_captures_observed_ports_and_services(self):
        manifest = json.loads(self.read(MANIFEST))

        self.assertEqual(manifest["id"], "openvpn")

        services = {
            item["name"]: item["ownership"]
            for item in manifest["services"]
        }
        self.assertEqual(
            services["openvpn-server@server-tcp-1194.service"],
            "legacy",
        )
        self.assertEqual(
            services["openvpn-server@server-udp-2200.service"],
            "legacy",
        )
        self.assertEqual(
            services["hamada-openvpn-ws.service"],
            "legacy",
        )

        public_tcp = {
            item["port"] for item in manifest["ports"]["public_tcp"]
        }
        public_udp = {
            item["port"] for item in manifest["ports"]["public_udp"]
        }
        internal_tcp = {
            item["port"] for item in manifest["ports"]["internal_tcp"]
        }

        self.assertIn(1194, public_tcp)
        self.assertIn(2200, public_udp)
        self.assertIn(10082, internal_tcp)

    def test_manifest_keeps_firewall_legacy_owned(self):
        manifest = json.loads(self.read(MANIFEST))
        self.assertEqual(manifest["firewall"]["ownership"], "legacy")
        self.assertIn(
            "NAT/forwarding rules are legacy-owned",
            manifest["firewall"]["requirements"],
        )


if __name__ == "__main__":
    unittest.main()

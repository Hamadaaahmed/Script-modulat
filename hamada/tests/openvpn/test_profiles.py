import importlib
import unittest


CA_CERT = """-----BEGIN CERTIFICATE-----
TEST-CA-CONTENT
LINE-TWO
-----END CERTIFICATE-----"""


class OpenVPNProfileRendererTests(unittest.TestCase):
    def renderer_class(self):
        module = importlib.import_module(
            "hamada.modules.openvpn.profiles"
        )
        return module.OpenVPNProfileRenderer

    def renderer(self):
        return self.renderer_class()(
            domain="vpn.example.test",
            ca_certificate=CA_CERT,
        )

    def assert_common_client_contract(self, profile):
        self.assertIn("client\n", profile)
        self.assertIn("dev tun\n", profile)
        self.assertIn("resolv-retry infinite\n", profile)
        self.assertIn("nobind\n", profile)
        self.assertIn("persist-key\n", profile)
        self.assertIn("persist-tun\n", profile)
        self.assertIn("auth-user-pass\n", profile)
        self.assertIn("remote-cert-tls server\n", profile)
        self.assertIn("verb 3\n", profile)
        self.assertIn("<ca>\n", profile)
        self.assertIn(CA_CERT, profile)
        self.assertIn("\n</ca>\n", profile)

    def test_tcp_profile_matches_observed_contract(self):
        profile = self.renderer().tcp()

        self.assert_common_client_contract(profile)
        self.assertIn("proto tcp-client\n", profile)
        self.assertIn(
            "remote vpn.example.test 1194\n",
            profile,
        )

    def test_udp_profile_matches_observed_contract(self):
        profile = self.renderer().udp()

        self.assert_common_client_contract(profile)
        self.assertIn("proto udp\n", profile)
        self.assertIn(
            "remote vpn.example.test 2200\n",
            profile,
        )

    def test_websocket_443_is_tcp_profile_with_ws_remote(self):
        renderer = self.renderer()

        base = renderer.tcp()
        profile = renderer.websocket(443)

        expected = base.replace(
            "remote vpn.example.test 1194\n",
            "remote vpn.example.test 443\n",
            1,
        )

        self.assertEqual(profile, expected)
        self.assertIn("proto tcp-client\n", profile)

    def test_websocket_80_is_tcp_profile_with_ws_remote(self):
        renderer = self.renderer()

        base = renderer.tcp()
        profile = renderer.websocket(80)

        expected = base.replace(
            "remote vpn.example.test 1194\n",
            "remote vpn.example.test 80\n",
            1,
        )

        self.assertEqual(profile, expected)
        self.assertIn("proto tcp-client\n", profile)

    def test_unsupported_websocket_port_is_rejected(self):
        with self.assertRaises(ValueError):
            self.renderer().websocket(8080)

    def test_domain_rejects_whitespace_and_empty_values(self):
        renderer_class = self.renderer_class()

        for domain in (
            "",
            "   ",
            "vpn example.test",
            "vpn.example.test\nother.example.test",
        ):
            with self.subTest(domain=domain):
                with self.assertRaises(ValueError):
                    renderer_class(
                        domain=domain,
                        ca_certificate=CA_CERT,
                    )

    def test_ca_certificate_is_required(self):
        renderer_class = self.renderer_class()

        for ca_certificate in ("", "   "):
            with self.subTest(ca_certificate=ca_certificate):
                with self.assertRaises(ValueError):
                    renderer_class(
                        domain="vpn.example.test",
                        ca_certificate=ca_certificate,
                    )

    def test_renderer_surface_has_no_mutation_methods(self):
        renderer_class = self.renderer_class()

        forbidden = {
            "write",
            "save",
            "install",
            "apply",
            "restart",
            "start",
            "stop",
            "enable",
            "disable",
            "delete",
            "remove",
        }

        public = {
            name
            for name in dir(renderer_class)
            if not name.startswith("_")
        }

        self.assertTrue(
            forbidden.isdisjoint(public),
            "mutation surface exposed: {}".format(
                sorted(forbidden.intersection(public))
            ),
        )


if __name__ == "__main__":
    unittest.main()

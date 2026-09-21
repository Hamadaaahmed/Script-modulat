import unittest

from hamada.modules.openvpn.system import CommandResult, OpenVPNSystem


class OpenVPNSystemTests(unittest.TestCase):
    def test_service_checks_use_argument_arrays(self):
        calls = []

        def runner(args, **kwargs):
            calls.append((args, kwargs))
            return CommandResult(args, "", "", 0)

        system = OpenVPNSystem(runner)
        self.assertTrue(
            system.service_active(
                "openvpn-server@server-tcp-1194.service"
            )
        )
        self.assertTrue(
            system.service_enabled(
                "openvpn-server@server-tcp-1194.service"
            )
        )

        self.assertEqual(
            calls[0][0],
            [
                "systemctl",
                "is-active",
                "--quiet",
                "openvpn-server@server-tcp-1194.service",
            ],
        )
        self.assertNotIn("shell", calls[0][1])

    def test_listener_inspection_is_read_only(self):
        output = """\
tcp LISTEN 0 128 0.0.0.0:1194 0.0.0.0:*
tcp LISTEN 0 128 127.0.0.1:10082 0.0.0.0:*
udp UNCONN 0 0 0.0.0.0:2200 0.0.0.0:*
"""
        self.assertTrue(
            OpenVPNSystem._listener_present(
                output, "tcp", "0.0.0.0", 1194
            )
        )
        self.assertTrue(
            OpenVPNSystem._listener_present(
                output, "tcp", "127.0.0.1", 10082
            )
        )
        self.assertTrue(
            OpenVPNSystem._listener_present(
                output, "udp", "0.0.0.0", 2200
            )
        )
        self.assertFalse(
            OpenVPNSystem._listener_present(
                output, "udp", "0.0.0.0", 1194
            )
        )

    def test_phase3a_adapter_exposes_no_mutation_methods(self):
        system = OpenVPNSystem(lambda args, **kwargs: CommandResult(args))
        for name in (
            "start",
            "stop",
            "restart",
            "enable",
            "disable",
            "write_config",
            "install",
            "iptables",
        ):
            self.assertFalse(hasattr(system, name), name)


if __name__ == "__main__":
    unittest.main()

import contextlib
import io
import unittest
from unittest import mock

from hamada.modules.openvpn.health import OpenVPNHealthItem
from hamada.runtime import cli


class FakeHealthyOpenVPNHealthService:
    def inspect(self):
        return (
            OpenVPNHealthItem(
                "openvpn_binary",
                True,
                "/usr/sbin/openvpn",
            ),
            OpenVPNHealthItem(
                "tcp_config",
                True,
                "OK",
            ),
            OpenVPNHealthItem(
                "listener:tcp:1194",
                True,
                "TCP 1194",
            ),
        )


class FakeUnhealthyOpenVPNHealthService:
    def inspect(self):
        return (
            OpenVPNHealthItem(
                "openvpn_binary",
                True,
                "/usr/sbin/openvpn",
            ),
            OpenVPNHealthItem(
                "udp_config",
                False,
                "proto expected ('udp4',), found ('tcp4',)",
            ),
        )


class OpenVPNHealthCLITests(unittest.TestCase):
    def run_cli(self, service):
        stdout = io.StringIO()
        stderr = io.StringIO()

        with mock.patch.object(
            cli,
            "OpenVPNHealthService",
            return_value=service,
            create=True,
        ):
            with contextlib.redirect_stdout(stdout):
                with contextlib.redirect_stderr(stderr):
                    rc = cli.main(["openvpn-health"])

        return rc, stdout.getvalue(), stderr.getvalue()

    def test_openvpn_health_command_is_registered(self):
        rc, stdout, stderr = self.run_cli(
            FakeHealthyOpenVPNHealthService()
        )

        self.assertEqual(rc, cli.EXIT_OK)
        self.assertEqual(stderr, "")
        self.assertIn(
            "PASS openvpn_binary /usr/sbin/openvpn",
            stdout,
        )
        self.assertIn("PASS tcp_config OK", stdout)
        self.assertIn(
            "PASS listener:tcp:1194 TCP 1194",
            stdout,
        )
        self.assertIn("summary=3/3 passed", stdout)

    def test_openvpn_health_failure_returns_runtime_exit(self):
        rc, stdout, stderr = self.run_cli(
            FakeUnhealthyOpenVPNHealthService()
        )

        self.assertEqual(rc, cli.EXIT_RUNTIME)
        self.assertEqual(stderr, "")
        self.assertIn(
            "PASS openvpn_binary /usr/sbin/openvpn",
            stdout,
        )
        self.assertIn("FAIL udp_config ", stdout)
        self.assertIn("summary=1/2 passed", stdout)

    def test_openvpn_health_empty_result_is_runtime_failure(self):
        class EmptyHealthService:
            def inspect(self):
                return ()

        rc, stdout, stderr = self.run_cli(
            EmptyHealthService()
        )

        self.assertEqual(rc, cli.EXIT_RUNTIME)
        self.assertEqual(stderr, "")
        self.assertIn("summary=0/0 passed", stdout)


if __name__ == "__main__":
    unittest.main()

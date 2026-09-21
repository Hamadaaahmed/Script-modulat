import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MAIN_INSTALLER = ROOT / "install" / "install.sh"
SSH_INSTALLER = ROOT / "install" / "modules" / "ssh" / "install.sh"
README = ROOT / "hamada" / "modules" / "openvpn" / "README.md"


class OpenVPNNATPersistenceTests(unittest.TestCase):
    """Regression coverage for OpenVPN NAT surviving host reboot."""

    def read(self, path):
        return path.read_text(encoding="utf-8")

    def assert_firewall_lifecycle(self, source):
        expected = (
            "/usr/local/sbin/hamada-openvpn-firewall",
            "/etc/systemd/system/hamada-openvpn-firewall.service",
            "10.8.0.0/24",
            "10.9.0.0/24",
            "iptables -t nat -C POSTROUTING",
            "iptables -t nat -A POSTROUTING",
            '-o "$IFACE" -j MASQUERADE',
            "After=network-online.target",
            "Wants=network-online.target",
            "Before=openvpn-server@server-tcp-1194.service "
            "openvpn-server@server-udp-2200.service",
            "Type=oneshot",
            "ExecStart=/usr/local/sbin/hamada-openvpn-firewall",
            "RemainAfterExit=yes",
            "WantedBy=multi-user.target",
            "systemctl enable --now hamada-openvpn-firewall.service",
        )
        for value in expected:
            self.assertIn(value, source)

    def test_main_installer_installs_persistent_openvpn_nat_service(self):
        self.assert_firewall_lifecycle(self.read(MAIN_INSTALLER))

    def test_ssh_installer_installs_persistent_openvpn_nat_service(self):
        self.assert_firewall_lifecycle(self.read(SSH_INSTALLER))

    def test_firewall_helper_is_idempotent(self):
        for path in (MAIN_INSTALLER, SSH_INSTALLER):
            source = self.read(path)
            self.assertIn(
                'iptables -t nat -C POSTROUTING \\\n'
                '    -s "$NET" -o "$IFACE" -j MASQUERADE 2>/dev/null ||',
                source,
            )

    def test_both_openvpn_networks_are_owned_by_helper(self):
        for path in (MAIN_INSTALLER, SSH_INSTALLER):
            source = self.read(path)
            self.assertIn(
                "for NET in 10.8.0.0/24 10.9.0.0/24; do",
                source,
            )

    def test_forwarding_remains_persistent(self):
        for path in (MAIN_INSTALLER, SSH_INSTALLER):
            source = self.read(path)
            self.assertIn("net.ipv4.ip_forward=1", source)
            self.assertIn(
                "grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf",
                source,
            )

    def test_core_ownership_remains_read_only(self):
        readme = self.read(README)
        self.assertIn(
            "NAT/forwarding remains legacy/shared infrastructure.",
            readme,
        )
        self.assertIn("- iptables/firewall/NAT", readme)

    def test_no_netfilter_persistent_dependency_added(self):
        for path in (MAIN_INSTALLER, SSH_INSTALLER):
            source = self.read(path)
            self.assertNotIn("netfilter-persistent", source)


if __name__ == "__main__":
    unittest.main()

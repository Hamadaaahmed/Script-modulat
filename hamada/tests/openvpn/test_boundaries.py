import json
import unittest
from pathlib import Path

from hamada.core.validation import validate_manifest


ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "hamada" / "manifests" / "openvpn.json"


class OpenVPNPhase3ABoundaryTests(unittest.TestCase):
    def manifest(self):
        return json.loads(MANIFEST.read_text(encoding="utf-8"))

    def test_manifest_is_phase3a_reference(self):
        manifest = self.manifest()
        self.assertEqual(manifest["migration"]["status"], "reference")
        self.assertEqual(manifest["migration"]["phase"], "3A")
        self.assertIn(
            "read-only runtime inspection",
            manifest["migration"]["core_ownership"],
        )

    def test_runtime_mutation_remains_legacy_owned(self):
        manifest = self.manifest()
        legacy = manifest["migration"]["legacy_ownership"]
        for item in (
            "OpenVPN installation",
            "PKI generation",
            "server configuration writes",
            "systemd service lifecycle",
            "NAT and forwarding rules",
            "Nginx and HAProxy routing",
        ):
            self.assertIn(item, legacy)

    def test_linux_accounts_are_external_pam_dependency(self):
        manifest = self.manifest()
        self.assertTrue(manifest["accounts"]["supported"])
        self.assertEqual(
            manifest["accounts"]["backend"],
            "linux-pam-external",
        )
        self.assertIn(
            "Linux account lifecycle",
            manifest["migration"]["external_ownership"],
        )
        self.assertIn(
            "PAM account backend",
            manifest["migration"]["external_ownership"],
        )

    def test_services_remain_legacy_owned(self):
        manifest = self.manifest()
        self.assertTrue(manifest["services"])
        self.assertTrue(
            all(
                service["ownership"] == "legacy"
                for service in manifest["services"]
            )
        )

    def test_firewall_remains_legacy_owned(self):
        manifest = self.manifest()
        self.assertEqual(manifest["firewall"]["ownership"], "legacy")

    def test_manifest_passes_foundation_validation(self):
        findings = validate_manifest(self.manifest(), "openvpn.json")
        errors = [
            finding
            for finding in findings
            if getattr(finding, "severity", "ERROR") == "ERROR"
        ]
        self.assertEqual(errors, [])


if __name__ == "__main__":
    unittest.main()

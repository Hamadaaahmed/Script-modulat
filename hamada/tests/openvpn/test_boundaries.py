import json
import unittest
from pathlib import Path

from hamada.core.validation import validate_manifest


ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "hamada" / "manifests" / "openvpn.json"


class OpenVPNPhase3ABoundaryTests(unittest.TestCase):
    def manifest(self):
        return json.loads(MANIFEST.read_text(encoding="utf-8"))

    def test_read_only_runtime_inspection_remains_core_owned(self):
        manifest = self.manifest()
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

    def test_phase3f_manifest_records_profile_rendering_core_ownership(self):
        manifest = self.manifest()

        self.assertEqual(
            manifest["migration"]["status"],
            "partial",
        )
        self.assertEqual(
            manifest["migration"]["phase"],
            "3F",
        )
        self.assertIn(
            "deterministic client profile rendering (no filesystem writes)",
            manifest["migration"]["core_ownership"],
        )

    def test_phase3f_profile_filesystem_publication_remains_legacy_owned(self):
        manifest = self.manifest()
        legacy = manifest["migration"]["legacy_ownership"]

        self.assertIn(
            "client profile filesystem writes and publication",
            legacy,
        )
        self.assertNotIn(
            "client profile generation",
            legacy,
        )

    def test_phase3f_readme_documents_profile_rendering_boundary(self):
        readme = (
            ROOT
            / "hamada"
            / "modules"
            / "openvpn"
            / "README.md"
        ).read_text(encoding="utf-8")

        self.assertIn(
            "deterministic client-profile rendering",
            readme,
        )
        self.assertIn(
            "does not write or publish profile files",
            readme,
        )
        self.assertIn(
            "filesystem writes and publication remain legacy-owned",
            readme,
        )

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

import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
class IntegrationBoundaryTests(unittest.TestCase):
    def test_installer_deploys_core_before_public_commands(self):
        s=(ROOT/'setup.sh').read_text(); deploy=s.index('hamada-runtime-deploy deploy'); install=s.index('name="$(basename "$source_file")"')
        self.assertLess(deploy,install)
    def test_bootstrap_has_idempotent_runtime_hook(self):
        self.assertIn('hamada-runtime-deploy deploy',(ROOT/'scripts/bootstrap-full-install.sh').read_text())

    def test_openvpn_health_public_command_is_installable(self):
        command = ROOT/'usr/bin/openvpn-health'
        self.assertTrue(command.is_file())
        self.assertIn(
            'hamada.runtime.cli',
            command.read_text(),
        )
        setup = (ROOT/'setup.sh').read_text()
        self.assertIn(
            'find usr/bin -maxdepth 1 -type f -print',
            setup,
        )
    def test_updater_deploys_core_before_command_loop_and_uses_runtime_rollback(self):
        s=(ROOT/'usr/bin/hamada-update').read_text(); deploy=s.index('hamada-runtime-deploy" deploy'); loop=s.index('while IFS= read -r name;',deploy)
        self.assertLess(deploy,loop)
        core_deployed=s.index('CORE_DEPLOYED=1',deploy)
        self.assertLess(deploy,core_deployed); self.assertLess(core_deployed,loop)
        self.assertIn('[ "$CORE_DEPLOYED" -eq 1 ]',s)
        self.assertIn('hamada-runtime-deploy" rollback --root /opt/hamada',s)
    def test_schema_unchanged_for_phase25(self):
        # Phase 2.5 uses the existing optional migration.status=partial schema.
        s=(ROOT/'hamada/schemas/module.schema.json').read_text(); self.assertIn('"partial"',s)
    def test_out_of_scope_module_source_not_added(self):
        modules=ROOT/'hamada/modules'; self.assertEqual(sorted(p.name for p in modules.iterdir() if p.is_dir() and p.name!='__pycache__'),['openvpn','ssh'])

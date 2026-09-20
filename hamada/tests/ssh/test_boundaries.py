import json, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
class Phase2BoundaryTests(unittest.TestCase):
    def test_public_commands_remain_legacy_unchanged_in_cutover_status(self):
        for n in ['add-ssh','trial-ssh','renew-ssh','del-ssh','cek-ssh','show-ssh','menu-ssh']: self.assertTrue((ROOT/'usr/bin'/n).is_file())
    def test_manifest_partial_truth(self):
        d=json.loads((ROOT/'hamada/manifests/ssh.json').read_text()); self.assertEqual(d['migration']['status'],'partial'); self.assertIn('Dropbear',d['migration']['legacy_ownership']); self.assertIn('add-ssh',d['migration']['legacy_ownership']); self.assertIn('renew-ssh public command uses SSH Core after runtime preflight',d['migration']['migrated_ownership'])
    def test_no_out_of_scope_module_created(self):
        mods=ROOT/'hamada/modules'; self.assertEqual(sorted(p.name for p in mods.iterdir() if p.is_dir() and not p.name.startswith('__')),['ssh'])

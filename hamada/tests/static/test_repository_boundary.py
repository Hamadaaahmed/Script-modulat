import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
class BoundaryTests(unittest.TestCase):
 def test_foundation_not_wired_into_legacy_entrypoints(self):
  for rel in ('setup.sh','scripts/bootstrap-full-install.sh','install/install.sh'):
   text=(ROOT/rel).read_text(encoding='utf-8',errors='replace')
   self.assertNotIn('hamada-foundation',text)
   self.assertNotIn('python3 -m hamada.core',text)
 def test_public_usr_bin_still_exists(self):
  self.assertTrue((ROOT/'usr/bin/menu').exists())
  self.assertTrue((ROOT/'usr/bin/xrayctl').exists())
  self.assertTrue((ROOT/'usr/bin/hamada-update').exists())

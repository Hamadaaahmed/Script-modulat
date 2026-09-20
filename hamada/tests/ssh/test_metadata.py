import os, stat, tempfile, unittest
from pathlib import Path
from hamada.modules.ssh.metadata import SSHMetadataStore, parse_legacy_text
from hamada.modules.ssh.errors import MetadataError

class MetadataTests(unittest.TestCase):
    def test_parse_legacy_metadata(self):
        d=parse_legacy_text("USERNAME='alice'\nPASSWORD='secret'\nEXP_DATE='2026-10-01'\nTRIAL_MINUTES='30'\nEXPIRE_TS='123'\nEXPIRE_HUMAN='x'\nLIMIT_GB='5'\n")
        self.assertEqual(d['USERNAME'],'alice'); self.assertEqual(d['PASSWORD'],'secret'); self.assertEqual(d['LIMIT_GB'],'5')
    def test_parser_does_not_execute_shell(self):
        with self.assertRaises(MetadataError): parse_legacy_text("USERNAME=$(touch /tmp/hamada-should-not-exist)\nBAD LINE; touch /tmp/x\n")
        self.assertFalse(Path('/tmp/hamada-should-not-exist').exists())
    def test_atomic_write_and_permissions(self):
        with tempfile.TemporaryDirectory() as td:
            s=SSHMetadataStore(td); s.write('alice',{'USERNAME':'alice','PASSWORD':'secret','EXP_DATE':'2026-10-01'})
            p=Path(td)/'alice.conf'; self.assertEqual(stat.S_IMODE(p.stat().st_mode),0o600); self.assertEqual(s.read('alice')['PASSWORD'],'secret')
            s.update('alice',{'EXP_DATE':'2026-11-01'}); self.assertEqual(s.read('alice')['EXP_DATE'],'2026-11-01')
            self.assertFalse(any(x.name.startswith('.alice.') for x in Path(td).iterdir()))
    def test_missing_file(self):
        with tempfile.TemporaryDirectory() as td:
            with self.assertRaises(FileNotFoundError): SSHMetadataStore(td).read('missing')

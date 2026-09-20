import tempfile, unittest
from datetime import date
from pathlib import Path
from hamada.modules.ssh.accounts import SSHAccountService
from hamada.modules.ssh.metadata import SSHMetadataStore, parse_legacy_text

class FakeSystem:
    def __init__(self, expiry): self.expiry=expiry; self.set_calls=[]
    def user_exists(self,u): return True
    def get_expiry(self,u): return self.expiry
    def set_expiry(self,u,e): self.set_calls.append((u,e)); self.expiry=e
    def active_sessions(self,u): return 0

class RenewParityTests(unittest.TestCase):
    def run_case(self, old, add, expected):
        with tempfile.TemporaryDirectory() as td:
            store=SSHMetadataStore(td); path=Path(td)/'alice.conf'
            original="USERNAME='alice'\nPASSWORD='secret'\nEXP_DATE='2020-01-01'\nLIMIT_GB='5'\nEXTRA_FIELD='kept'\n"
            path.write_text(original); path.chmod(0o600)
            sys=FakeSystem(old); svc=SSHAccountService(store,sys,today=lambda:date(2026,9,20)); r=svc.renew_account('alice',add)
            self.assertEqual(r['expiry'],expected); self.assertEqual(sys.set_calls,[('alice',expected)])
            out=path.read_text(); self.assertIn(f"EXP_DATE='{expected}'",out); self.assertIn("PASSWORD='secret'",out); self.assertIn("EXTRA_FIELD='kept'",out)
    def test_active_parity(self): self.run_case('2026-09-25',3,'2026-09-28')
    def test_expired_parity(self): self.run_case('2026-09-10',2,'2026-09-22')
    def test_zero_day_parity(self): self.run_case('2026-09-25',0,'2026-09-25')
    def test_realistic_metadata_fixtures(self):
        samples=[
            "USERNAME='a'\nPASSWORD='p'\nEXP_DATE='2026-10-01'\nDOMAIN='x'\n",
            "USERNAME='a'\nPASSWORD='p'\nEXP_DATE='2026-01-01'\nTRIAL_MINUTES='30'\nEXPIRE_TS='1'\nEXPIRE_HUMAN='x'\n",
            "USERNAME='a'\nPASSWORD='p'\nEXP_DATE='2026-10-01'\nLIMIT_GB='9'\nEXTRA='v'\nEMPTY=''\n",
        ]
        for text in samples: self.assertEqual(parse_legacy_text(text)['USERNAME'],'a')
        with self.assertRaises(Exception): parse_legacy_text("BAD LINE; touch /tmp/no\n")

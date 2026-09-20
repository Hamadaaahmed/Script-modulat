import tempfile, unittest
from datetime import date, datetime, timezone
from hamada.modules.ssh.accounts import SSHAccountService
from hamada.modules.ssh.metadata import SSHMetadataStore
from hamada.modules.ssh.errors import AccountAlreadyExists, InvalidUsername, InvalidPassword, InvalidExpiry
from hamada.modules.ssh.system import CommandResult

class FakeSystem:
    def __init__(self): self.users={}; self.sessions={}; self.calls=[]
    def user_exists(self,u): return u in self.users
    def create_user(self,u): self.calls.append(('create',u)); self.users[u]={'expiry':''}
    def set_password(self,u,p): self.calls.append(('password',u,p))
    def set_expiry(self,u,e): self.calls.append(('expiry',u,e)); self.users[u]['expiry']=e
    def get_expiry(self,u): return self.users[u]['expiry']
    def terminate_sessions(self,u): self.calls.append(('terminate',u)); self.sessions[u]=0
    def delete_user(self,u): self.calls.append(('delete',u)); del self.users[u]
    def active_sessions(self,u): return self.sessions.get(u,0)

class AccountTests(unittest.TestCase):
    def service(self,td):
        sys=FakeSystem(); svc=SSHAccountService(SSHMetadataStore(td),sys,today=lambda:date(2026,9,20),now=lambda:datetime(2026,9,20,12,0,tzinfo=timezone.utc)); return svc,sys
    def test_username_validation(self):
        for u in ['alice','a_b','trial1','a-1']: SSHAccountService.validate_username(u)
        for u in ['bad name','bad;name','-option','../root','AUpper','a'*33,'']:
            with self.assertRaises(InvalidUsername,msg=u): SSHAccountService.validate_username(u)
    def test_password_validation(self):
        SSHAccountService.validate_password('abc123')
        for p in ['', 'a:b', 'a\nb']:
            with self.assertRaises(InvalidPassword): SSHAccountService.validate_password(p)
    def test_create_duplicate_list_status(self):
        with tempfile.TemporaryDirectory() as td:
            svc,sys=self.service(td); d=svc.create_account('alice','secret',5,'vpn.test'); self.assertEqual(d['EXP_DATE'],'2026-09-25'); self.assertEqual(svc.list_accounts(),['alice'])
            with self.assertRaises(AccountAlreadyExists): svc.create_account('alice','x',1)
            sys.sessions['alice']=2; st=svc.account_status('alice'); self.assertEqual(st.active_sessions,2); self.assertFalse(st.expired)
    def test_renew_legacy_semantics_active_and_expired(self):
        with tempfile.TemporaryDirectory() as td:
            svc,sys=self.service(td); svc.create_account('alice','secret',5); r=svc.renew_account('alice',3); self.assertEqual(r['left_days'],5); self.assertEqual(r['expiry'],'2026-09-28')
            sys.users['alice']['expiry']='2026-09-10'; r=svc.renew_account('alice',2); self.assertEqual(r['left_days'],0); self.assertEqual(r['expiry'],'2026-09-22')
    def test_zero_days_matches_legacy_numeric_acceptance(self):
        with tempfile.TemporaryDirectory() as td:
            svc,sys=self.service(td); svc.create_account('alice','secret',0); self.assertEqual(sys.users['alice']['expiry'],'2026-09-20'); svc.renew_account('alice',0)
    def test_delete_best_effort_missing_user(self):
        with tempfile.TemporaryDirectory() as td:
            svc,sys=self.service(td); svc.metadata.write('ghost',{'USERNAME':'ghost'}); r=svc.delete_account('ghost'); self.assertFalse(r['user_existed']); self.assertTrue(r['metadata_deleted'])
    def test_trial_values(self):
        with tempfile.TemporaryDirectory() as td:
            svc,_=self.service(td); v=svc.trial_values(30); self.assertRegex(v['username'],r'^trial[0-9a-f]{4}$'); self.assertRegex(v['password'],r'^[0-9a-f]{8}$'); self.assertEqual(v['minutes'],30)
            with self.assertRaises(InvalidExpiry): svc.trial_values(0)

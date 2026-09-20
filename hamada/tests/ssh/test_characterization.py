import re, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
class LegacyCharacterizationTests(unittest.TestCase):
    def read(self,n): return (ROOT/'usr/bin'/n).read_text()
    def test_add_contract_and_payloads(self):
        s=self.read('add-ssh');
        for x in ['useradd -M -s /bin/bash','chpasswd','chage -E','ssh ws.txt','ovpn ws.txt','chmod 600','OpenVPN TCP','UDP Custom','SLOWDNS']: self.assertIn(x,s)
    def test_trial_contract(self):
        s=self.read('trial-ssh');
        for x in ['openssl rand -hex 2','openssl rand -hex 4','systemd-run','TRIAL_MINUTES','EXPIRE_TS','EXPIRE_HUMAN','add-ssh']: self.assertIn(x,s)
    def test_renew_contract(self):
        s=(ROOT/'legacy/usr/bin/renew-ssh').read_text(); self.assertIn('TOTAL_DAYS=$((LEFT_DAYS + DAYS))',s); self.assertIn('chage -E',s); self.assertIn("sed -i \"s/^EXP_DATE=.*/EXP_DATE='$EXP_DATE'/\"",s)
    def test_delete_contract(self):
        s=self.read('del-ssh');
        for x in ['pkill -u','userdel','rm -f "$STORE/${USERNAME}.conf"']: self.assertIn(x,s)
    def test_show_mixed_compatibility_and_unsafe_source_captured(self):
        s=self.read('show-ssh');
        for x in ['source "$STORE/${u}.conf"','Dropbear','OpenVPN TCP','UDP Custom','slowdns_account_block','SSH Payloads']: self.assertIn(x,s)
    def test_active_contract(self):
        s=self.read('cek-ssh'); self.assertIn('pgrep -u',s); self.assertIn('ss -ntp',s); self.assertIn('Online accounts:',s)
    def test_menu_numbering(self):
        s=(ROOT/'install/modules/ssh/menu.sh').read_text();
        for x in ['[1] Create SSH Account','[2] Trial SSH Account','[3] Renew SSH Account','[4] Delete SSH Account','[5] Check Active Logins','[6] Show SSH Accounts']: self.assertIn(x,s)

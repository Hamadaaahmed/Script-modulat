from pathlib import Path
import shutil

class SSHHealthItem:
    def __init__(self, name, ok, detail):
        self.name=name; self.ok=ok; self.detail=detail

def read_only_health(config='/etc/ssh/sshd_config', metadata='/etc/hamada/ssh-accounts'):
    checks=[]
    checks.append(SSHHealthItem('sshd_binary', shutil.which('sshd') is not None, shutil.which('sshd') or 'missing'))
    checks.append(SSHHealthItem('sshd_config', Path(config).is_file(), config))
    checks.append(SSHHealthItem('metadata_root', Path(metadata).is_dir(), metadata))
    return checks

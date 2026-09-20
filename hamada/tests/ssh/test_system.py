import unittest
from hamada.modules.ssh.system import LinuxAccountSystem, CommandResult

class SystemAdapterTests(unittest.TestCase):
    def test_argument_arrays_and_password_stdin(self):
        calls=[]
        def runner(args, **kw): calls.append((args,kw)); return CommandResult(tuple(args),'','','0' if False else 0)
        s=LinuxAccountSystem(runner); s.create_user('alice'); s.set_password('alice','secret'); s.set_expiry('alice','2026-10-01'); s.terminate_sessions('alice'); s.delete_user('alice')
        self.assertEqual(calls[0][0],['useradd','-M','-s','/bin/bash','alice']); self.assertEqual(calls[1][0],['chpasswd']); self.assertEqual(calls[1][1]['input_text'],'alice:secret\n')
        self.assertNotIn('shell', calls[1][1])

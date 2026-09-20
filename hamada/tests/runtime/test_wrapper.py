import os, subprocess, tempfile, unittest
from pathlib import Path
PROJECT=Path(__file__).resolve().parents[3]
WRAPPER=PROJECT/'usr/bin/renew-ssh'
class WrapperTests(unittest.TestCase):
    def test_wrapper_has_no_repo_runtime_dependency(self):
        s=WRAPPER.read_text(); self.assertNotIn('/root/commercial-vps-autoscript',s); self.assertIn('/opt/hamada',s)
    def test_fallback_only_before_mutation_boundary(self):
        s=WRAPPER.read_text(); marker='# Mutation boundary:'; self.assertIn(marker,s)
        after=s.split(marker,1)[1]; self.assertNotIn('exec "$LEGACY"',after)
    def test_no_recursive_fallback(self):
        legacy=(PROJECT/'legacy/usr/bin/renew-ssh').read_text(); self.assertNotIn('/opt/hamada/legacy/renew-ssh',legacy); self.assertNotIn('hamada.runtime.cli',legacy)
    def test_missing_core_uses_explicit_legacy(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td); (root/'legacy').mkdir(); fallback=root/'legacy/renew-ssh'; fallback.write_text('#!/bin/sh\necho LEGACY\n'); fallback.chmod(0o755)
            cp=subprocess.run(['bash',str(WRAPPER)],env={'HAMADA_HOME':td,'HAMADA_PYTHON':'/missing/python','PATH':'/usr/bin:/bin'},capture_output=True,text=True)
            self.assertEqual(cp.returncode,0); self.assertEqual(cp.stdout.strip(),'LEGACY')
    def test_missing_core_and_fallback_fails_clear(self):
        with tempfile.TemporaryDirectory() as td:
            cp=subprocess.run(['bash',str(WRAPPER)],env={'HAMADA_HOME':td,'HAMADA_PYTHON':'/missing/python','PATH':'/usr/bin:/bin'},capture_output=True,text=True)
            self.assertEqual(cp.returncode,20); self.assertIn('fallback missing',cp.stderr)
    def test_post_mutation_failure_does_not_fallback(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'runtime'; (root/'current/hamada').mkdir(parents=True); (root/'legacy').mkdir()
            marker=Path(td)/'fallback-ran'
            fallback=root/'legacy/renew-ssh'; fallback.write_text(f'#!/bin/sh\ntouch {marker}\n'); fallback.chmod(0o755)
            fake=Path(td)/'python'; fake.write_text('#!/bin/sh\ncase "$*" in *runtime-check*) exit 0;; *ssh-renew*) exit 40;; esac\n'); fake.chmod(0o755)
            env=os.environ.copy(); env.update({'HAMADA_HOME':str(root),'HAMADA_PYTHON':str(fake)})
            cp=subprocess.run(['bash',str(WRAPPER)],env=env,capture_output=True,text=True)
            self.assertEqual(cp.returncode,40); self.assertFalse(marker.exists())


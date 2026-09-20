import json, os, shutil, stat, tempfile, unittest
from pathlib import Path
from unittest import mock
from hamada.runtime.deployment import RuntimeDeployment, DeploymentError

PROJECT=Path(__file__).resolve().parents[3]

class DeploymentTests(unittest.TestCase):
    def copy_source(self, td, version='2.5.1', fallback_marker=None):
        src=Path(td)/'src'; src.mkdir(parents=True)
        shutil.copytree(PROJECT/'hamada',src/'hamada',ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
        (src/'hamada/VERSION').write_text(version+'\n')
        (src/'legacy/usr/bin').mkdir(parents=True)
        if fallback_marker is None:
            shutil.copy2(PROJECT/'legacy/usr/bin/renew-ssh',src/'legacy/usr/bin/renew-ssh')
        else:
            fallback=src/'legacy/usr/bin/renew-ssh'
            fallback.write_text('#!/bin/sh\necho %s\n' % fallback_marker)
            fallback.chmod(0o755)
        return src

    def stable_text(self, root):
        return (Path(root)/'legacy/renew-ssh').read_text()

    def runtime_state(self, root):
        path=Path(root)/'state/runtime.json'
        return json.loads(path.read_text()) if path.is_file() else None

    def test_deploy_activate_status_and_idempotency(self):
        with tempfile.TemporaryDirectory() as td:
            src=self.copy_source(td); root=Path(td)/'runtime'; d=RuntimeDeployment(root)
            v=d.deploy(src); self.assertEqual(d.active_version(),v); self.assertTrue(d.status().healthy)
            self.assertEqual(d.deploy(src),v); self.assertEqual(d.active_version(),v)
            self.assertTrue((root/'legacy/renew-ssh').is_file())
            self.assertEqual((root/'legacy/renew-ssh').read_bytes(),(d.active_release()/'legacy/renew-ssh').read_bytes())
            self.assertFalse((root/'legacy/renew-ssh').stat().st_mode & stat.S_IWOTH)
            self.assertTrue(os.access(str(root/'legacy/renew-ssh'),os.X_OK))

    def test_release_identity_includes_legacy_fallback_content(self):
        with tempfile.TemporaryDirectory() as td:
            a=self.copy_source(Path(td)/'a','2.5.1','FALLBACK_A')
            b=self.copy_source(Path(td)/'b','2.5.1','FALLBACK_B')
            self.assertNotEqual(RuntimeDeployment.source_version(a),RuntimeDeployment.source_version(b))

    def test_runtime_independent_from_source_checkout(self):
        with tempfile.TemporaryDirectory() as td:
            src=self.copy_source(td); root=Path(td)/'runtime'; d=RuntimeDeployment(root); d.deploy(src)
            shutil.rmtree(src)
            self.assertTrue(d.status().healthy)
            active=d.active_release(); self.assertIsNotNone(active)
            import subprocess, sys
            cp=subprocess.run([sys.executable,'-I','-c',f"import sys;sys.path.insert(0,{str(active)!r});import hamada.modules.ssh.accounts;print('OK')"],capture_output=True,text=True)
            self.assertEqual(cp.returncode,0,cp.stderr); self.assertEqual(cp.stdout.strip(),'OK')

    def test_upgrade_and_rollback_restores_matching_fallback(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'runtime'; d=RuntimeDeployment(root)
            a=self.copy_source(Path(td)/'a','2.5.1-a','FALLBACK_A'); va=d.deploy(a)
            self.assertEqual(d.active_version(),va); self.assertIn('FALLBACK_A',self.stable_text(root))
            b=self.copy_source(Path(td)/'b','2.5.1-b','FALLBACK_B'); vb=d.deploy(b)
            self.assertEqual(d.active_version(),vb); self.assertEqual(d.previous_version(),va); self.assertIn('FALLBACK_B',self.stable_text(root))
            self.assertEqual(d.rollback(),va)
            self.assertEqual(d.active_version(),va); self.assertEqual(d.previous_version(),vb)
            self.assertIn('FALLBACK_A',self.stable_text(root))
            self.assertEqual((root/'legacy/renew-ssh').read_bytes(),(d.active_release()/'legacy/renew-ssh').read_bytes())
            state=self.runtime_state(root); self.assertEqual(state['active'],va); self.assertEqual(state['previous'],vb)
            self.assertTrue(d.status().healthy)

    def test_broken_release_rejected_before_activation(self):
        with tempfile.TemporaryDirectory() as td:
            src=self.copy_source(td); (src/'hamada/modules/ssh/accounts.py').unlink(); root=Path(td)/'runtime'; d=RuntimeDeployment(root)
            with self.assertRaises(DeploymentError): d.deploy(src)
            self.assertIsNone(d.active_version())

    def test_invalid_version_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            src=self.copy_source(td); (src/'hamada/VERSION').write_text('../bad\n')
            with self.assertRaises(DeploymentError): RuntimeDeployment(Path(td)/'r').deploy(src)

    def test_world_writable_required_file_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            src=self.copy_source(td); os.chmod(src/'hamada/modules/ssh/accounts.py',0o666)
            with self.assertRaises(DeploymentError): RuntimeDeployment(Path(td)/'r').deploy(src)

    def test_checksum_corruption_detected(self):
        with tempfile.TemporaryDirectory() as td:
            src=self.copy_source(td); d=RuntimeDeployment(Path(td)/'r'); d.deploy(src); active=d.active_release()
            with (active/'hamada/modules/ssh/accounts.py').open('a') as h: h.write('\n# corrupt\n')
            self.assertFalse(d.status().healthy)

    def test_status_detects_stable_fallback_mismatch(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'r'; src=self.copy_source(td,fallback_marker='A'); d=RuntimeDeployment(root); d.deploy(src)
            (root/'legacy/renew-ssh').write_text('#!/bin/sh\necho WRONG\n'); (root/'legacy/renew-ssh').chmod(0o755)
            self.assertFalse(d.status().healthy)

    def test_status_detects_stale_runtime_state(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'r'; src=self.copy_source(td,fallback_marker='A'); d=RuntimeDeployment(root); d.deploy(src)
            state=self.runtime_state(root); state['active']='stale-release'
            (root/'state/runtime.json').write_text(json.dumps(state)+'\n')
            self.assertFalse(d.status().healthy)

    def test_missing_rollback_target(self):
        with tempfile.TemporaryDirectory() as td:
            d=RuntimeDeployment(Path(td)/'r')
            with self.assertRaises(DeploymentError): d.rollback()

    def test_rollback_target_outside_runtime_root_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'runtime'; root.mkdir(); outside=Path(td)/'outside'; outside.mkdir()
            os.symlink(str(outside),root/'previous')
            with self.assertRaisesRegex(DeploymentError,'previous runtime target invalid'):
                RuntimeDeployment(root).rollback()

    def test_rollback_target_missing_fallback_rejected_before_mutation(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'runtime'; d=RuntimeDeployment(root)
            a=self.copy_source(Path(td)/'a','2.5.1-a','A'); va=d.deploy(a)
            b=self.copy_source(Path(td)/'b','2.5.1-b','B'); vb=d.deploy(b)
            old_state=self.runtime_state(root); old_stable=self.stable_text(root)
            (d._release(va)/'legacy/renew-ssh').unlink()
            with self.assertRaises(DeploymentError): d.rollback()
            self.assertEqual(d.active_version(),vb); self.assertEqual(self.stable_text(root),old_stable); self.assertEqual(self.runtime_state(root),old_state)

    def test_rollback_target_unusable_fallback_rejected_before_mutation(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'runtime'; d=RuntimeDeployment(root)
            a=self.copy_source(Path(td)/'a','2.5.1-a','A'); va=d.deploy(a)
            b=self.copy_source(Path(td)/'b','2.5.1-b','B'); vb=d.deploy(b)
            old_state=self.runtime_state(root); old_stable=self.stable_text(root)
            fallback=d._release(va)/'legacy/renew-ssh'; fallback.chmod(0o644)
            with self.assertRaisesRegex(DeploymentError,'not executable'): d.rollback()
            self.assertEqual(d.active_version(),vb); self.assertEqual(self.stable_text(root),old_stable); self.assertEqual(self.runtime_state(root),old_state)

    def test_rollback_target_fallback_integrity_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'runtime'; d=RuntimeDeployment(root)
            a=self.copy_source(Path(td)/'a','2.5.1-a','A'); va=d.deploy(a)
            b=self.copy_source(Path(td)/'b','2.5.1-b','B'); vb=d.deploy(b)
            old_state=self.runtime_state(root); old_stable=self.stable_text(root)
            fallback=d._release(va)/'legacy/renew-ssh'; fallback.write_text('#!/bin/sh\necho TAMPERED\n'); fallback.chmod(0o755)
            with self.assertRaisesRegex(DeploymentError,'checksum'): d.rollback()
            self.assertEqual(d.active_version(),vb); self.assertEqual(self.stable_text(root),old_stable); self.assertEqual(self.runtime_state(root),old_state)

    def test_stable_fallback_replacement_failure_not_success(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'runtime'; d=RuntimeDeployment(root)
            a=self.copy_source(Path(td)/'a','2.5.1-a','A'); va=d.deploy(a)
            b=self.copy_source(Path(td)/'b','2.5.1-b','B'); vb=d.deploy(b)
            old_state=self.runtime_state(root); old_stable=self.stable_text(root)
            with mock.patch.object(d,'_replace_stable_fallback',side_effect=OSError('replace failed')):
                with self.assertRaisesRegex(DeploymentError,'pre-rollback Runtime set was restored'): d.rollback()
            self.assertEqual(d.active_version(),vb); self.assertEqual(d.previous_version(),va)
            self.assertEqual(self.stable_text(root),old_stable); self.assertEqual(self.runtime_state(root),old_state)

    def test_core_activation_failure_restores_fallback_and_state(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'runtime'; d=RuntimeDeployment(root)
            a=self.copy_source(Path(td)/'a','2.5.1-a','A'); va=d.deploy(a)
            b=self.copy_source(Path(td)/'b','2.5.1-b','B'); vb=d.deploy(b)
            old_state=self.runtime_state(root); old_stable=self.stable_text(root); real_atomic=d._atomic_link; failed=[False]
            def fail_once(link,target):
                if link == d.current and not failed[0]:
                    failed[0]=True; raise OSError('activation failed')
                return real_atomic(link,target)
            with mock.patch.object(d,'_atomic_link',side_effect=fail_once):
                with self.assertRaisesRegex(DeploymentError,'pre-rollback Runtime set was restored'): d.rollback()
            self.assertEqual(d.active_version(),vb); self.assertEqual(d.previous_version(),va)
            self.assertEqual(self.stable_text(root),old_stable); self.assertEqual(self.runtime_state(root),old_state)
            self.assertTrue(d.status().healthy)

    def test_state_write_failure_restores_runtime_set_and_old_state(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'runtime'; d=RuntimeDeployment(root)
            a=self.copy_source(Path(td)/'a','2.5.1-a','A'); va=d.deploy(a)
            b=self.copy_source(Path(td)/'b','2.5.1-b','B'); vb=d.deploy(b)
            old_state=self.runtime_state(root); old_stable=self.stable_text(root); real_write=d._write_json_atomic
            def fail_runtime_state(path,data):
                if path == d.state/'runtime.json': raise OSError('state write failed')
                return real_write(path,data)
            with mock.patch.object(d,'_write_json_atomic',side_effect=fail_runtime_state):
                with self.assertRaisesRegex(DeploymentError,'pre-rollback Runtime set was restored'): d.rollback()
            self.assertEqual(d.active_version(),vb); self.assertEqual(d.previous_version(),va)
            self.assertEqual(self.stable_text(root),old_stable); self.assertEqual(self.runtime_state(root),old_state)
            self.assertTrue(d.status().healthy)

    def test_upgrade_success_keeps_core_fallback_state_coherent(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'runtime'; d=RuntimeDeployment(root)
            a=self.copy_source(Path(td)/'a','2.5.2-a','FALLBACK_A'); va=d.deploy(a)
            b=self.copy_source(Path(td)/'b','2.5.2-b','FALLBACK_B'); vb=d.deploy(b)
            self.assertEqual(d.active_version(),vb); self.assertEqual(d.previous_version(),va)
            self.assertIn('FALLBACK_B',self.stable_text(root))
            state=self.runtime_state(root); self.assertEqual(state['active'],vb); self.assertEqual(state['previous'],va)
            self.assertTrue(d.status().healthy)

    def test_deploy_current_activation_failure_restores_predeploy_runtime(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'runtime'; d=RuntimeDeployment(root)
            a=self.copy_source(Path(td)/'a','2.5.2-a','FALLBACK_A'); va=d.deploy(a)
            old_state=self.runtime_state(root); old_stable=self.stable_text(root); old_previous=d.previous_version()
            b=self.copy_source(Path(td)/'b','2.5.2-b','FALLBACK_B')
            real_atomic=d._atomic_link; failed=[False]
            def fail_current_once(link,target):
                if link == d.current and target.name != va and not failed[0]:
                    failed[0]=True; raise OSError('current activation failed')
                return real_atomic(link,target)
            with mock.patch.object(d,'_atomic_link',side_effect=fail_current_once):
                with self.assertRaisesRegex(DeploymentError,'pre-deploy Runtime set was restored'):
                    d.deploy(b)
            self.assertEqual(d.active_version(),va); self.assertEqual(d.previous_version(),old_previous)
            self.assertEqual(self.stable_text(root),old_stable); self.assertEqual(self.runtime_state(root),old_state)
            self.assertTrue(d.status().healthy)

    def test_deploy_state_write_failure_restores_predeploy_runtime(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'runtime'; d=RuntimeDeployment(root)
            a=self.copy_source(Path(td)/'a','2.5.2-a','FALLBACK_A'); va=d.deploy(a)
            old_state=self.runtime_state(root); old_stable=self.stable_text(root); old_previous=d.previous_version()
            b=self.copy_source(Path(td)/'b','2.5.2-b','FALLBACK_B')
            real_write=d._write_json_atomic
            def fail_runtime_state(path,data):
                if path == d.state/'runtime.json': raise OSError('runtime state write failed')
                return real_write(path,data)
            with mock.patch.object(d,'_write_json_atomic',side_effect=fail_runtime_state):
                with self.assertRaisesRegex(DeploymentError,'pre-deploy Runtime set was restored'):
                    d.deploy(b)
            self.assertEqual(d.active_version(),va); self.assertEqual(d.previous_version(),old_previous)
            self.assertEqual(self.stable_text(root),old_stable); self.assertEqual(self.runtime_state(root),old_state)
            self.assertTrue(d.status().healthy)

    def test_first_install_activation_failure_restores_absent_runtime(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'runtime'; d=RuntimeDeployment(root)
            src=self.copy_source(Path(td)/'src','2.5.2-first','FALLBACK_FIRST')
            real_atomic=d._atomic_link; failed=[False]
            def fail_current_once(link,target):
                if link == d.current and not failed[0]:
                    failed[0]=True; raise OSError('current activation failed')
                return real_atomic(link,target)
            with mock.patch.object(d,'_atomic_link',side_effect=fail_current_once):
                with self.assertRaisesRegex(DeploymentError,'pre-deploy Runtime set was restored'):
                    d.deploy(src)
            self.assertIsNone(d.active_version()); self.assertIsNone(d.previous_version())
            self.assertFalse((root/'legacy/renew-ssh').exists())
            self.assertFalse((root/'state/runtime.json').exists())
            self.assertFalse(d.status().healthy)

    def test_deploy_fallback_replacement_failure_preserves_healthy_runtime(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'runtime'; d=RuntimeDeployment(root)
            a=self.copy_source(Path(td)/'a','2.5.2-a','FALLBACK_A'); va=d.deploy(a)
            old_state=self.runtime_state(root); old_stable=self.stable_text(root); old_previous=d.previous_version()
            b=self.copy_source(Path(td)/'b','2.5.2-b','FALLBACK_B')
            with mock.patch.object(d,'_replace_stable_fallback',side_effect=OSError('fallback replace failed')):
                with self.assertRaisesRegex(DeploymentError,'pre-deploy Runtime set was restored'):
                    d.deploy(b)
            self.assertEqual(d.active_version(),va); self.assertEqual(d.previous_version(),old_previous)
            self.assertEqual(self.stable_text(root),old_stable); self.assertEqual(self.runtime_state(root),old_state)
            self.assertTrue(d.status().healthy)

    def test_deploy_previous_pointer_failure_restores_predeploy_runtime(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'runtime'; d=RuntimeDeployment(root)
            a=self.copy_source(Path(td)/'a','2.5.2-a','FALLBACK_A'); va=d.deploy(a)
            old_state=self.runtime_state(root); old_stable=self.stable_text(root); old_previous=d.previous_version()
            b=self.copy_source(Path(td)/'b','2.5.2-b','FALLBACK_B')
            real_atomic=d._atomic_link; failed=[False]
            def fail_previous_once(link,target):
                if link == d.previous and not failed[0]:
                    failed[0]=True; raise OSError('previous pointer failed')
                return real_atomic(link,target)
            with mock.patch.object(d,'_atomic_link',side_effect=fail_previous_once):
                with self.assertRaisesRegex(DeploymentError,'pre-deploy Runtime set was restored'):
                    d.deploy(b)
            self.assertEqual(d.active_version(),va); self.assertEqual(d.previous_version(),old_previous)
            self.assertEqual(self.stable_text(root),old_stable); self.assertEqual(self.runtime_state(root),old_state)
            self.assertTrue(d.status().healthy)

    def test_deploy_recovery_failure_requires_manual_verification(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)/'runtime'; d=RuntimeDeployment(root)
            a=self.copy_source(Path(td)/'a','2.5.2-a','FALLBACK_A'); va=d.deploy(a)
            b=self.copy_source(Path(td)/'b','2.5.2-b','FALLBACK_B')
            real_atomic=d._atomic_link; failed=[False]
            def fail_current_once(link,target):
                if link == d.current and target.name != va and not failed[0]:
                    failed[0]=True; raise OSError('current activation failed')
                return real_atomic(link,target)
            with mock.patch.object(d,'_atomic_link',side_effect=fail_current_once), \
                 mock.patch.object(d,'_restore_stable_fallback',side_effect=OSError('fallback recovery failed')):
                with self.assertRaisesRegex(DeploymentError,'manual verification required'):
                    d.deploy(b)
            self.assertEqual(d.active_version(),va)
            self.assertFalse(d.status().healthy)

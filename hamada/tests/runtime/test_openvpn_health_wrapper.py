import os
import subprocess
import tempfile
import unittest
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[3]
WRAPPER = PROJECT / "usr/bin/openvpn-health"


class OpenVPNHealthWrapperTests(unittest.TestCase):
    def test_wrapper_exists_and_is_executable(self):
        self.assertTrue(WRAPPER.is_file())
        self.assertTrue(os.access(str(WRAPPER), os.X_OK))

    def test_wrapper_has_no_source_checkout_dependency(self):
        text = WRAPPER.read_text()
        self.assertNotIn("/root/commercial-vps-autoscript", text)
        self.assertIn("/opt/hamada", text)
        self.assertIn("hamada.runtime.cli", text)
        self.assertIn("openvpn-health", text)

    def test_missing_python_returns_runtime_failure(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "current/hamada").mkdir(parents=True)

            env = os.environ.copy()
            env.update(
                {
                    "HAMADA_HOME": str(root),
                    "HAMADA_PYTHON": "/definitely/missing/python",
                }
            )

            cp = subprocess.run(
                ["bash", str(WRAPPER)],
                env=env,
                capture_output=True,
                text=True,
            )

            self.assertEqual(cp.returncode, 20)
            self.assertIn(
                "HAMADA OpenVPN Core unavailable",
                cp.stderr,
            )

    def test_missing_core_returns_runtime_failure(self):
        with tempfile.TemporaryDirectory() as td:
            fake_python = Path(td) / "python"
            fake_python.write_text("#!/bin/sh\nexit 0\n")
            fake_python.chmod(0o755)

            env = os.environ.copy()
            env.update(
                {
                    "HAMADA_HOME": str(Path(td) / "runtime"),
                    "HAMADA_PYTHON": str(fake_python),
                }
            )

            cp = subprocess.run(
                ["bash", str(WRAPPER)],
                env=env,
                capture_output=True,
                text=True,
            )

            self.assertEqual(cp.returncode, 20)
            self.assertIn(
                "HAMADA OpenVPN Core unavailable",
                cp.stderr,
            )

    def test_delegates_to_active_runtime_and_preserves_exit_code(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "runtime"
            (root / "current/hamada").mkdir(parents=True)

            args_file = Path(td) / "args"
            env_file = Path(td) / "pythonpath"
            fake_python = Path(td) / "python"

            fake_python.write_text(
                "#!/bin/sh\n"
                'printf "%s\\n" "$*" > "$HAMADA_TEST_ARGS"\n'
                'printf "%s\\n" "$PYTHONPATH" > "$HAMADA_TEST_PYTHONPATH"\n'
                "exit 20\n"
            )
            fake_python.chmod(0o755)

            env = os.environ.copy()
            env.update(
                {
                    "HAMADA_HOME": str(root),
                    "HAMADA_PYTHON": str(fake_python),
                    "HAMADA_TEST_ARGS": str(args_file),
                    "HAMADA_TEST_PYTHONPATH": str(env_file),
                }
            )

            cp = subprocess.run(
                ["bash", str(WRAPPER)],
                env=env,
                capture_output=True,
                text=True,
            )

            self.assertEqual(cp.returncode, 20)
            self.assertEqual(
                args_file.read_text().strip(),
                "-m hamada.runtime.cli openvpn-health "
                "--root {}".format(root),
            )
            self.assertEqual(
                env_file.read_text().strip(),
                str(root / "current"),
            )


if __name__ == "__main__":
    unittest.main()

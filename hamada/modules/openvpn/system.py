"""Read-only OpenVPN system adapter.

Phase 3A deliberately exposes inspection only. There are no start, stop,
restart, enable, firewall or configuration mutation methods.
"""
import shutil
import subprocess
from pathlib import Path
from typing import Optional, Tuple

from .errors import OpenVPNSystemError


class CommandResult:
    def __init__(self, args, stdout="", stderr="", returncode=0):
        self.args = tuple(args)
        self.stdout = stdout
        self.stderr = stderr
        self.returncode = returncode


class OpenVPNSystem:
    PAM_PLUGIN_CANDIDATES = (
        "/usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so",
        "/usr/lib/openvpn/openvpn-plugin-auth-pam.so",
    )

    def __init__(self, runner=None) -> None:
        self.runner = runner or self._run

    @staticmethod
    def _run(args, *, check=False):
        cp = subprocess.run(
            list(args),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            check=False,
        )
        if check and cp.returncode != 0:
            raise OpenVPNSystemError(
                "command failed ({}): {}: {}".format(
                    cp.returncode,
                    args[0],
                    cp.stderr.strip(),
                )
            )
        return CommandResult(args, cp.stdout, cp.stderr, cp.returncode)

    @staticmethod
    def binary_path(name: str) -> Optional[str]:
        return shutil.which(name)

    @staticmethod
    def file_exists(path: str) -> bool:
        return Path(path).is_file()

    def pam_plugin(self) -> Optional[str]:
        for path in self.PAM_PLUGIN_CANDIDATES:
            if self.file_exists(path):
                return path
        return None

    def service_active(self, service: str) -> bool:
        result = self.runner(
            ["systemctl", "is-active", "--quiet", service],
            check=False,
        )
        return result.returncode == 0

    def service_enabled(self, service: str) -> bool:
        result = self.runner(
            ["systemctl", "is-enabled", "--quiet", service],
            check=False,
        )
        return result.returncode == 0

    def listening_sockets(self) -> str:
        return self.runner(["ss", "-lntup"], check=False).stdout

    def tcp_listener_present(self, host: str, port: int) -> bool:
        return self._listener_present(
            self.listening_sockets(), "tcp", host, port
        )

    def udp_listener_present(self, host: str, port: int) -> bool:
        return self._listener_present(
            self.listening_sockets(), "udp", host, port
        )

    @staticmethod
    def _listener_present(
        output: str,
        protocol: str,
        host: str,
        port: int,
    ) -> bool:
        suffix = ":{}".format(port)
        for line in output.splitlines():
            fields = line.split()
            if not fields:
                continue

            socket_proto = fields[0].lower()
            if protocol == "tcp" and not socket_proto.startswith("tcp"):
                continue
            if protocol == "udp" and not socket_proto.startswith("udp"):
                continue

            if host == "127.0.0.1":
                if any(
                    field.startswith("127.0.0.1:") and field.endswith(suffix)
                    for field in fields
                ):
                    return True
            elif any(field.endswith(suffix) for field in fields):
                return True

        return False

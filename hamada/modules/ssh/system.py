"""Linux system adapter for SSH accounts. No shell=True is used."""
import pwd, subprocess
from .errors import SystemCommandError

class CommandResult:
    def __init__(self, args, stdout="", stderr="", returncode=0):
        self.args=tuple(args); self.stdout=stdout; self.stderr=stderr; self.returncode=returncode

class LinuxAccountSystem:
    def __init__(self, runner=None) -> None:
        self.runner = runner or self._run

    @staticmethod
    def _run(args, *, input_text=None, check=True):
        cp = subprocess.run(list(args), input=input_text, universal_newlines=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        if check and cp.returncode != 0:
            raise SystemCommandError(f"command failed ({cp.returncode}): {args[0]}: {cp.stderr.strip()}")
        return CommandResult(tuple(args), cp.stdout, cp.stderr, cp.returncode)

    def user_exists(self, username: str) -> bool:
        try: pwd.getpwnam(username); return True
        except KeyError: return False

    def create_user(self, username: str) -> None:
        self.runner(["useradd", "-M", "-s", "/bin/bash", username])

    def set_password(self, username: str, password: str) -> None:
        self.runner(["chpasswd"], input_text=f"{username}:{password}\n")

    def set_expiry(self, username: str, expiry: str) -> None:
        self.runner(["chage", "-E", expiry, username])

    def get_expiry(self, username: str) -> str:
        result = self.runner(["chage", "-l", username])
        for line in result.stdout.splitlines():
            if line.startswith("Account expires") and ":" in line:
                return line.split(":", 1)[1].strip()
        return ""

    def terminate_sessions(self, username: str) -> None:
        self.runner(["pkill", "-u", username], check=False)

    def delete_user(self, username: str) -> None:
        self.runner(["userdel", username])

    def active_sessions(self, username: str) -> int:
        pids = self.runner(["pgrep", "-u", username], check=False)
        if pids.returncode != 0 or not pids.stdout.strip(): return 0
        sockets = self.runner(["ss", "-ntp"], check=False).stdout
        return sum(1 for pid in pids.stdout.split() if f"pid={pid}," in sockets)

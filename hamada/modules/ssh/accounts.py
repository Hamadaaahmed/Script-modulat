import re, secrets
from datetime import date, datetime, timedelta, timezone
from typing import Dict, List
from .errors import AccountAlreadyExists, AccountNotFound, InvalidExpiry, InvalidPassword, InvalidUsername, MetadataError
from .metadata import SSHMetadataStore
from .system import LinuxAccountSystem

# Conservative Linux username subset. Creation uses this stricter rule; existing legacy accounts
# are discovered from metadata and Linux state without being rewritten.
USERNAME_RE = re.compile(r"^[a-z_][a-z0-9_-]{0,31}$")

class AccountStatus:
    def __init__(self, username, exists, expiry, expired, active_sessions, metadata):
        self.username=username; self.exists=exists; self.expiry=expiry; self.expired=expired; self.active_sessions=active_sessions; self.metadata=metadata

class SSHAccountService:
    def __init__(self, metadata=None, system=None, today=None, now=None) -> None:
        self.metadata = metadata or SSHMetadataStore()
        self.system = system or LinuxAccountSystem()
        self._today = today or date.today
        self._now = now or (lambda: datetime.now(timezone.utc))

    @staticmethod
    def validate_username(username: str) -> str:
        if not USERNAME_RE.fullmatch(username or "") or username.startswith("-"):
            raise InvalidUsername("username must match ^[a-z_][a-z0-9_-]{0,31}$")
        return username

    @staticmethod
    def validate_password(password: str) -> str:
        if not password or "\n" in password or "\r" in password or ":" in password:
            raise InvalidPassword("password must be non-empty and cannot contain colon/newline")
        return password

    @staticmethod
    def validate_days(days: int) -> int:
        if isinstance(days, bool) or not isinstance(days, int) or days < 0:
            raise InvalidExpiry("days must be a non-negative integer")
        return days

    def create_account(self, username: str, password: str, days: int, domain: str = "") -> Dict[str, str]:
        self.validate_username(username); self.validate_password(password); self.validate_days(days)
        if self.system.user_exists(username): raise AccountAlreadyExists(username)
        expiry = (self._today() + timedelta(days=days)).isoformat()
        self.system.create_user(username)
        try:
            self.system.set_password(username, password)
            self.system.set_expiry(username, expiry)
            data = {"USERNAME": username, "PASSWORD": password, "EXP_DATE": expiry, "DOMAIN": domain}
            self.metadata.write(username, data)
            return data
        except Exception:
            self.system.terminate_sessions(username)
            try: self.system.delete_user(username)
            except Exception: pass
            raise

    def list_accounts(self) -> List[str]:
        return [u for u in self.metadata.list_usernames() if self.system.user_exists(u)]

    def get_account(self, username: str) -> Dict[str, str]:
        try: return self.metadata.read(username)
        except FileNotFoundError as exc: raise AccountNotFound(username) from exc

    @staticmethod
    def _days_left(expiry: str, today: date) -> int:
        if not expiry or expiry == "never": return 0
        try: target = datetime.strptime(expiry, "%Y-%m-%d").date()
        except ValueError: return 0
        return max((target - today).days, 0)

    def renew_account(self, username: str, add_days: int) -> Dict[str, object]:
        self.validate_days(add_days)
        if not self.system.user_exists(username): raise AccountNotFound(username)
        old_expiry = self.system.get_expiry(username)
        left = self._days_left(old_expiry, self._today())
        total = left + add_days
        new_expiry = (self._today() + timedelta(days=total)).isoformat()
        self.system.set_expiry(username, new_expiry)
        try:
            self.metadata.update_exp_date_compat(username, new_expiry)
        except FileNotFoundError:
            pass  # legacy renew updates metadata only when it exists
        return {"username": username, "old_expiry": old_expiry, "left_days": left, "added_days": add_days, "total_days": total, "expiry": new_expiry}

    def delete_account(self, username: str) -> Dict[str, object]:
        user_existed = self.system.user_exists(username)
        self.system.terminate_sessions(username)
        system_error = None
        if user_existed:
            try: self.system.delete_user(username)
            except Exception as exc: system_error = exc
        metadata_deleted = self.metadata.delete(username)
        if system_error: raise system_error
        return {"username": username, "user_existed": user_existed, "metadata_deleted": metadata_deleted}

    def account_status(self, username: str) -> AccountStatus:
        exists = self.system.user_exists(username)
        metadata = {}
        try: metadata = self.metadata.read(username)
        except FileNotFoundError: pass
        expiry = self.system.get_expiry(username) if exists else metadata.get("EXP_DATE", "")
        expired = bool(expiry and expiry != "never" and self._days_left(expiry, self._today()) == 0 and expiry < self._today().isoformat())
        sessions = self.system.active_sessions(username) if exists else 0
        return AccountStatus(username, exists, expiry, expired, sessions, metadata)

    def trial_values(self, minutes: int) -> Dict[str, object]:
        if isinstance(minutes, bool) or not isinstance(minutes, int) or minutes <= 0: raise InvalidExpiry("minutes must be greater than 0")
        user = "trial" + secrets.token_hex(2)
        password = secrets.token_hex(4)
        expires = self._now() + timedelta(minutes=minutes)
        return {"username": user, "password": password, "minutes": minutes, "expire_ts": int(expires.timestamp()), "expire_human": expires.astimezone().strftime("%Y-%m-%d %H:%M:%S")}

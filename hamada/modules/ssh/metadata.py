"""Safe compatibility reader/writer for legacy KEY='VALUE' SSH account files."""
import os, re, tempfile
from pathlib import Path
from typing import Dict, List, Mapping, Union
from .errors import MetadataError

KEY_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")
LINE_RE = re.compile(r"^([A-Z][A-Z0-9_]*)=(.*)$")


def _decode_value(raw: str) -> str:
    raw = raw.strip()
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "'\"":
        quote = raw[0]
        value = raw[1:-1]
        if quote == "'":
            return value
        # Legacy files do not require shell expansion. Decode only simple escaped quote/backslash.
        return value.replace('\\"', '"').replace('\\\\', '\\')
    return raw


def parse_legacy_text(text: str) -> Dict[str, str]:
    data = {}
    for number, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = LINE_RE.fullmatch(line)
        if not match:
            raise MetadataError(f"invalid metadata line {number}")
        key, raw = match.groups()
        data[key] = _decode_value(raw)
    return data


def _encode_value(value: object) -> str:
    value = str(value)
    if "\n" in value or "\r" in value or "\x00" in value:
        raise MetadataError("metadata values may not contain control line breaks")
    # Preserve legacy single-quoted format. A literal single quote cannot be represented safely
    # without shell syntax, so reject it rather than creating executable metadata.
    if "'" in value:
        raise MetadataError("single quote is not supported in legacy metadata values")
    return "'" + value + "'"


class SSHMetadataStore:
    def __init__(self, root: Union[str, Path] = "/etc/hamada/ssh-accounts") -> None:
        self.root = Path(root)

    def path_for(self, username: str) -> Path:
        if not username or "/" in username or "\\" in username or username in {".", ".."}:
            raise MetadataError("unsafe metadata username")
        return self.root / f"{username}.conf"

    def read(self, username: str) -> Dict[str, str]:
        path = self.path_for(username)
        if not path.is_file():
            raise FileNotFoundError(path)
        return parse_legacy_text(path.read_text(encoding="utf-8"))

    def list_usernames(self) -> List[str]:
        if not self.root.is_dir():
            return []
        return sorted(p.stem for p in self.root.glob("*.conf") if p.is_file())

    def write(self, username: str, data: Mapping[str, object]) -> None:
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        path = self.path_for(username)
        lines = []
        for key, value in data.items():
            if not KEY_RE.fullmatch(key):
                raise MetadataError(f"invalid metadata key: {key}")
            lines.append(f"{key}={_encode_value(value)}\n")
        fd, tmp_name = tempfile.mkstemp(prefix=f".{username}.", dir=self.root, text=True)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.writelines(lines)
                handle.flush(); os.fsync(handle.fileno())
            os.replace(tmp_name, path)
            os.chmod(path, 0o600)
        except Exception:
            try: os.unlink(tmp_name)
            except FileNotFoundError: pass
            raise

    def update(self, username: str, changes: Mapping[str, object]) -> Dict[str, str]:
        data = self.read(username)
        data.update({k: str(v) for k, v in changes.items()})
        self.write(username, data)
        return data


    def update_exp_date_compat(self, username: str, expiry: str) -> bool:
        """Atomically replace only EXP_DATE while preserving all other legacy text byte-for-byte."""
        path = self.path_for(username)
        if not path.is_file():
            return False
        original = path.read_text(encoding="utf-8")
        replacement = f"EXP_DATE={_encode_value(expiry)}"
        lines = original.splitlines(keepends=True)
        found = False
        output = []
        for line in lines:
            body = line.rstrip("\r\n")
            ending = line[len(body):]
            if body.startswith("EXP_DATE="):
                output.append(replacement + ending)
                found = True
            else:
                output.append(line)
        if not found:
            return False
        fd, tmp_name = tempfile.mkstemp(prefix=f".{username}.", dir=self.root, text=True)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write("".join(output)); handle.flush(); os.fsync(handle.fileno())
            os.replace(tmp_name, path); os.chmod(path, 0o600)
        except Exception:
            try: os.unlink(tmp_name)
            except FileNotFoundError: pass
            raise
        return True

    def delete(self, username: str) -> bool:
        path = self.path_for(username)
        try: path.unlink(); return True
        except FileNotFoundError: return False

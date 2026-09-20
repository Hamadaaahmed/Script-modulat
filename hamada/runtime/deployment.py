import fcntl, hashlib, json, os, shutil, stat, tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import Dict, Optional, Union

REQUIRED = (
    "hamada/__init__.py", "hamada/VERSION", "hamada/modules/ssh/accounts.py",
    "hamada/modules/ssh/metadata.py", "hamada/modules/ssh/system.py",
    "hamada/runtime/__init__.py", "hamada/runtime/cli.py", "hamada/runtime/deployment.py",
    "legacy/renew-ssh",
)

class DeploymentError(RuntimeError): pass

class RuntimeStatus:
    def __init__(self, root, active_version, previous_version, healthy):
        self.root=root; self.active_version=active_version; self.previous_version=previous_version; self.healthy=healthy


def _safe_version(value: str) -> str:
    if not value or value in {".", ".."} or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-" for c in value):
        raise DeploymentError("invalid release version")
    return value

class RuntimeDeployment:
    def __init__(self, root: Union[str, Path] = "/opt/hamada") -> None:
        self.root = Path(root)
        self.releases = self.root / "releases"
        self.state = self.root / "state"
        self.current = self.root / "current"
        self.previous = self.root / "previous"
        self.legacy = self.root / "legacy"
        self.lock_path = self.root / ".deploy.lock"

    def _inside(self, path: Path) -> bool:
        try: path.resolve(strict=False).relative_to(self.root.resolve(strict=False)); return True
        except ValueError: return False

    def _release(self, version: str) -> Path:
        version = _safe_version(version)
        path = self.releases / version
        if not self._inside(path): raise DeploymentError("release path escaped runtime root")
        return path

    @contextmanager
    def lock(self):
        self.root.mkdir(parents=True, exist_ok=True, mode=0o755)
        fd = os.open(self.lock_path, os.O_CREAT | os.O_RDWR, 0o600)
        try:
            try: fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as exc: raise DeploymentError("another runtime deployment is active") from exc
            yield
        finally:
            os.close(fd)

    @staticmethod
    def _source_runtime_files(source):
        files = [source / "hamada/__init__.py", source / "hamada/VERSION", source / "legacy/usr/bin/renew-ssh"]
        for rel in ("hamada/modules/ssh", "hamada/runtime"):
            files.extend(p for p in (source / rel).rglob("*") if p.is_file() and "__pycache__" not in p.parts and p.suffix != ".pyc")
        return sorted(set(files))

    @staticmethod
    def source_version(source):
        base = _safe_version((source / "hamada/VERSION").read_text(encoding="utf-8").strip())
        digest = hashlib.sha256()
        for path in RuntimeDeployment._source_runtime_files(source):
            if not path.is_file(): raise DeploymentError("runtime source file missing: " + path.relative_to(source).as_posix())
            digest.update(path.relative_to(source).as_posix().encode())
            digest.update(b"\0"); digest.update(path.read_bytes()); digest.update(b"\0")
        return _safe_version("{}-{}".format(base, digest.hexdigest()[:12]))

    @staticmethod
    def _checksum_tree(release: Path) -> Dict[str, str]:
        out = {}
        for path in sorted((release / "hamada").rglob("*")):
            if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc":
                rel = path.relative_to(release).as_posix()
                out[rel] = hashlib.sha256(path.read_bytes()).hexdigest()
        legacy = release / "legacy/renew-ssh"
        if legacy.is_file(): out[legacy.relative_to(release).as_posix()] = hashlib.sha256(legacy.read_bytes()).hexdigest()
        return out

    def _write_json_atomic(self, path: Path, data: dict) -> None:
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd, tmp = tempfile.mkstemp(prefix=".state.", dir=path.parent, text=True)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as h:
                json.dump(data, h, sort_keys=True, indent=2); h.write("\n"); h.flush(); os.fsync(h.fileno())
            os.replace(tmp, path)
        except Exception:
            try: os.unlink(tmp)
            except FileNotFoundError: pass
            raise

    def validate_release(self, release: Path) -> None:
        if not self._inside(release): raise DeploymentError("release outside runtime root")
        for rel in REQUIRED:
            f = release / rel
            if not f.is_file(): raise DeploymentError(f"required runtime file missing: {rel}")
            if f.stat().st_mode & stat.S_IWOTH: raise DeploymentError(f"world-writable runtime file: {rel}")
        fallback = release / "legacy/renew-ssh"
        if not os.access(str(fallback), os.X_OK): raise DeploymentError("legacy renew fallback is not executable")
        for py in (release / "hamada").rglob("*.py"):
            if py.stat().st_mode & stat.S_IWOTH: raise DeploymentError(f"world-writable runtime file: {py.name}")
            try: compile(py.read_text(encoding="utf-8"), str(py), "exec")
            except (OSError, SyntaxError) as exc: raise DeploymentError(f"python validation failed: {py.name}") from exc
        # Import without relying on the source checkout.
        import subprocess, sys
        cp = subprocess.run([sys.executable, "-I", "-c", "import sys; sys.path.insert(0, %r); import hamada.modules.ssh.accounts, hamada.runtime.cli" % str(release)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        if cp.returncode != 0: raise DeploymentError("runtime import validation failed: " + cp.stderr.strip())
        manifest = release / "release.json"
        if manifest.is_file():
            try: data = json.loads(manifest.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as exc: raise DeploymentError("invalid release integrity manifest") from exc
            expected = data.get("checksums", {})
            actual = self._checksum_tree(release)
            if expected != actual: raise DeploymentError("runtime checksum verification failed")

    def _atomic_link(self, link: Path, target: Path) -> None:
        if not self._inside(target): raise DeploymentError("activation target outside runtime root")
        if not target.is_dir(): raise DeploymentError("activation target missing")
        tmp = link.with_name("." + link.name + ".new")
        try: tmp.unlink()
        except FileNotFoundError: pass
        os.symlink(str(target), tmp)
        os.replace(tmp, link)

    def _prepare_stable_fallback(self, release: Path) -> Path:
        # validate_release verifies the release-local fallback against release.json.
        self.validate_release(release)
        source = release / "legacy/renew-ssh"
        self.legacy.mkdir(parents=True, exist_ok=True, mode=0o755)
        fd, tmp_name = tempfile.mkstemp(prefix=".renew-ssh.new.", dir=self.legacy)
        os.close(fd)
        tmp = Path(tmp_name)
        try:
            shutil.copy2(source, tmp)
            os.chmod(tmp, 0o755)
            with tmp.open("rb") as h: os.fsync(h.fileno())
            if tmp.stat().st_mode & stat.S_IWOTH: raise DeploymentError("prepared legacy fallback is world-writable")
            if not os.access(str(tmp), os.X_OK): raise DeploymentError("prepared legacy fallback is not executable")
            if hashlib.sha256(tmp.read_bytes()).hexdigest() != hashlib.sha256(source.read_bytes()).hexdigest():
                raise DeploymentError("prepared legacy fallback integrity mismatch")
            return tmp
        except Exception:
            try: tmp.unlink()
            except FileNotFoundError: pass
            raise

    def _replace_stable_fallback(self, prepared: Path) -> None:
        stable = self.legacy / "renew-ssh"
        os.replace(str(prepared), str(stable))

    def _backup_stable_fallback(self) -> Optional[Path]:
        stable = self.legacy / "renew-ssh"
        if not stable.is_file(): return None
        fd, tmp_name = tempfile.mkstemp(prefix=".renew-ssh.rollback-backup.", dir=self.legacy)
        os.close(fd)
        backup = Path(tmp_name)
        try:
            shutil.copy2(stable, backup)
            with backup.open("rb") as h: os.fsync(h.fileno())
            return backup
        except Exception:
            try: backup.unlink()
            except FileNotFoundError: pass
            raise

    def _restore_stable_fallback(self, backup: Optional[Path]) -> None:
        stable = self.legacy / "renew-ssh"
        if backup is None:
            try: stable.unlink()
            except FileNotFoundError: pass
            return
        os.replace(str(backup), str(stable))

    def _restore_link(self, link: Path, target: Optional[Path]) -> None:
        if target is None:
            try: link.unlink()
            except FileNotFoundError: pass
            return
        self._atomic_link(link, target)

    def _link_release_target(self, link: Path) -> Optional[Path]:
        if not link.is_symlink(): return None
        target = link.resolve(strict=False)
        return target if self._inside(target) and target.is_dir() else None

    def _snapshot_runtime_state(self) -> Optional[bytes]:
        path = self.state / "runtime.json"
        return path.read_bytes() if path.is_file() else None

    def _restore_runtime_state(self, snapshot: Optional[bytes]) -> None:
        path = self.state / "runtime.json"
        if snapshot is None:
            try: path.unlink()
            except FileNotFoundError: pass
            return
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd, tmp = tempfile.mkstemp(prefix=".state.restore.", dir=path.parent)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "wb") as h:
                h.write(snapshot); h.flush(); os.fsync(h.fileno())
            os.replace(tmp, path)
        except Exception:
            try: os.unlink(tmp)
            except FileNotFoundError: pass
            raise

    def _stable_fallback_matches(self, release: Path) -> bool:
        stable = self.legacy / "renew-ssh"
        source = release / "legacy/renew-ssh"
        if not stable.is_file() or not source.is_file(): return False
        if stable.stat().st_mode & stat.S_IWOTH: return False
        if not os.access(str(stable), os.X_OK): return False
        return hashlib.sha256(stable.read_bytes()).digest() == hashlib.sha256(source.read_bytes()).digest()

    def deploy(self, source: Union[str, Path]) -> str:
        source = Path(source).resolve()
        version = self.source_version(source)
        final = self._release(version)
        with self.lock():
            self.releases.mkdir(parents=True, exist_ok=True, mode=0o755)
            self.state.mkdir(parents=True, exist_ok=True, mode=0o700)
            self.legacy.mkdir(parents=True, exist_ok=True, mode=0o755)
            if not final.exists():
                staging = Path(tempfile.mkdtemp(prefix=f".{version}.staging.", dir=self.releases))
                try:
                    (staging / "hamada/modules/ssh").mkdir(parents=True)
                    (staging / "hamada/runtime").mkdir(parents=True)
                    shutil.copy2(source / "hamada/__init__.py", staging / "hamada/__init__.py")
                    shutil.copy2(source / "hamada/VERSION", staging / "hamada/VERSION")
                    for src_file in (source / "hamada/modules/ssh").glob("*.py"):
                        shutil.copy2(src_file, staging / "hamada/modules/ssh" / src_file.name)
                    for src_file in (source / "hamada/runtime").glob("*.py"):
                        shutil.copy2(src_file, staging / "hamada/runtime" / src_file.name)
                    legacy_src = source / "legacy/usr/bin/renew-ssh"
                    if not legacy_src.is_file(): raise DeploymentError("legacy renew fallback source missing")
                    (staging / "legacy").mkdir(mode=0o755)
                    shutil.copy2(legacy_src, staging / "legacy/renew-ssh")
                    os.chmod(staging / "legacy/renew-ssh", 0o755)
                    self.validate_release(staging)
                    checksums = self._checksum_tree(staging)
                    self._write_json_atomic(staging / "release.json", {"format":1,"version":version,"checksums":checksums})
                    os.chmod(staging / "release.json", 0o644)
                    os.replace(staging, final)
                except Exception:
                    shutil.rmtree(staging, ignore_errors=True); raise
            else:
                self.validate_release(final)

            # Validate and prepare all release-local inputs before the first authoritative
            # Runtime mutation, then snapshot the complete pre-deploy Runtime set.
            prepared = self._prepare_stable_fallback(final)
            backup = self._backup_stable_fallback()
            old_current = self.active_release()
            old_previous = self._link_release_target(self.previous)
            old_state = self._snapshot_runtime_state()
            mutation_started = False
            try:
                # These are independent atomic replacements, not one global transaction.
                # Treat fallback replacement as the mutation boundary because an exception
                # from that operation may still leave its destination changed.
                mutation_started = True
                self._replace_stable_fallback(prepared)
                if old_current and old_current != final:
                    self._atomic_link(self.previous, old_current)
                self._atomic_link(self.current, final)
                self.validate_release(final)
                if not self._stable_fallback_matches(final):
                    raise DeploymentError("stable legacy fallback does not match active release")
                self._write_json_atomic(self.state / "runtime.json", {"format":1,"active":version,"previous":self.previous_version()})
                if not self.status().healthy:
                    raise DeploymentError("post-deploy Runtime consistency verification failed")
            except Exception as exc:
                if not mutation_started:
                    raise
                recovery_errors=[]
                try: self._restore_stable_fallback(backup); backup=None
                except Exception as recovery_exc: recovery_errors.append("stable fallback: " + str(recovery_exc))
                try: self._restore_link(self.current, old_current)
                except Exception as recovery_exc: recovery_errors.append("current pointer: " + str(recovery_exc))
                try: self._restore_link(self.previous, old_previous)
                except Exception as recovery_exc: recovery_errors.append("previous pointer: " + str(recovery_exc))
                try: self._restore_runtime_state(old_state)
                except Exception as recovery_exc: recovery_errors.append("runtime state: " + str(recovery_exc))
                if recovery_errors:
                    raise DeploymentError("deploy failed and automatic recovery was incomplete; manual verification required (" + "; ".join(recovery_errors) + ")") from exc
                if old_current and not self.status().healthy:
                    raise DeploymentError("deploy failed; automatic recovery completed but Runtime health is not clean; manual verification required") from exc
                raise DeploymentError("deploy failed; pre-deploy Runtime set was restored: " + str(exc)) from exc
            finally:
                try: prepared.unlink()
                except FileNotFoundError: pass
                if backup is not None:
                    try: backup.unlink()
                    except FileNotFoundError: pass
            return version

    def active_release(self) -> Optional[Path]:
        if not self.current.is_symlink(): return None
        target = self.current.resolve(strict=False)
        return target if self._inside(target) and target.is_dir() else None

    def active_version(self) -> Optional[str]:
        r=self.active_release(); return r.name if r else None

    def previous_version(self) -> Optional[str]:
        if not self.previous.is_symlink(): return None
        t=self.previous.resolve(strict=False)
        return t.name if self._inside(t) and t.is_dir() else None

    def rollback(self) -> str:
        with self.lock():
            if not self.previous.is_symlink(): raise DeploymentError("no previous runtime release")
            target=self.previous.resolve(strict=False)
            if not self._inside(target) or not target.is_dir(): raise DeploymentError("previous runtime target invalid")

            # Validate the complete rollback release, including its versioned Legacy fallback
            # and checksum manifest, before changing either active Runtime path.
            self.validate_release(target)
            prepared = self._prepare_stable_fallback(target)
            backup = self._backup_stable_fallback()
            old_current = self.active_release()
            old_previous = target
            fallback_replaced = False
            try:
                # Two independent paths cannot be changed as one filesystem transaction.
                # Replace the validated fallback first. If any later step fails, restore the
                # exact pre-rollback fallback and pointers before returning an error.
                self._replace_stable_fallback(prepared)
                fallback_replaced = True
                self._atomic_link(self.current,target)
                if old_current and old_current != target: self._atomic_link(self.previous,old_current)
                if not self._stable_fallback_matches(target):
                    raise DeploymentError("rollback produced Core/Legacy fallback mismatch")
                self._write_json_atomic(self.state / "runtime.json", {"format":1,"active":target.name,"previous":self.previous_version()})
            except Exception as exc:
                recovery_errors=[]
                if fallback_replaced:
                    try: self._restore_stable_fallback(backup); backup=None
                    except Exception as recovery_exc: recovery_errors.append("stable fallback: " + str(recovery_exc))
                try: self._restore_link(self.current,old_current)
                except Exception as recovery_exc: recovery_errors.append("current pointer: " + str(recovery_exc))
                try: self._restore_link(self.previous,old_previous)
                except Exception as recovery_exc: recovery_errors.append("previous pointer: " + str(recovery_exc))
                if recovery_errors:
                    raise DeploymentError("rollback failed and automatic recovery was incomplete; manual verification required (" + "; ".join(recovery_errors) + ")") from exc
                raise DeploymentError("rollback failed; pre-rollback Runtime set was restored: " + str(exc)) from exc
            finally:
                try: prepared.unlink()
                except FileNotFoundError: pass
                if backup is not None:
                    try: backup.unlink()
                    except FileNotFoundError: pass
            return target.name

    def _state_matches_runtime(self, active: Path) -> bool:
        state_path = self.state / "runtime.json"
        if not state_path.is_file(): return False
        try: data = json.loads(state_path.read_text(encoding="utf-8"))
        except (OSError, ValueError): return False
        return data.get("active") == active.name and data.get("previous") == self.previous_version()

    def status(self) -> RuntimeStatus:
        active=self.active_release(); healthy=False
        if active:
            try:
                self.validate_release(active)
                if not self._stable_fallback_matches(active): raise DeploymentError("stable legacy fallback does not match active release")
                if not self._state_matches_runtime(active): raise DeploymentError("runtime state does not match active/previous pointers")
                healthy=True
            except DeploymentError: healthy=False
        return RuntimeStatus(str(self.root), active.name if active else None, self.previous_version(), healthy)

"""Small deterministic output standard for future HAMADA tooling."""
import os, sys

LEVELS = ("INFO", "OK", "WARN", "ERROR", "DEBUG")

def is_tty(stream=None):
    stream = stream or sys.stdout
    return bool(getattr(stream, "isatty", lambda: False)())

def emit(level, message, *, stream=None, debug=False):
    if level not in LEVELS:
        raise ValueError(f"unknown output level: {level}")
    if level == "DEBUG" and not (debug or os.environ.get("HAMADA_DEBUG") == "1"):
        return ""
    stream = stream or (sys.stderr if level == "ERROR" else sys.stdout)
    line = f"[{level}] {message}"
    print(line, file=stream)
    return line

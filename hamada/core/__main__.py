from pathlib import Path
import argparse
from .validation import validate_directory
from .output import emit

def main():
    p=argparse.ArgumentParser(prog="hamada-foundation",description="Phase 1 read-only enterprise foundation tooling")
    p.add_argument("command",choices=["validate","modules","ports"])
    p.add_argument("--manifests",default=str(Path(__file__).resolve().parents[1]/"manifests"))
    a=p.parse_args(); reg,findings=validate_directory(a.manifests)
    if a.command=="modules":
        for mid in reg.list_ids(): print(mid)
    elif a.command=="ports":
        for f in reg.port_findings(): emit(f.severity,f.message)
    else:
        for f in findings: emit(f.severity,f"{f.code}: {f.message}")
        emit("OK" if not [x for x in findings if x.severity=="ERROR"] else "ERROR",f"validated {len(reg.modules)} manifests; findings={len(findings)}")
    return 1 if any(x.severity=="ERROR" for x in findings) else 0
if __name__=="__main__": raise SystemExit(main())

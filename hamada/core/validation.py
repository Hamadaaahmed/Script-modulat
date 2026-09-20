"""Safe validation engine. No eval, shell sourcing or runtime mutation."""
from pathlib import Path
import json, re
from .registry import Finding, ModuleRegistry

ID_RE=re.compile(r"^[a-z0-9][a-z0-9-]{1,63}$")
ALLOWED_LIFECYCLE={"preflight","install","configure","validate","enable","start","verify","reconcile","migrate","uninstall"}
PORT_KEYS=("public_tcp","public_udp","internal_tcp","internal_udp")
REQUIRED=("schema_version","id","name","version","description","dependencies","conflicts","requirements","paths","services","ports","firewall","edge","accounts","healthchecks","lifecycle")

def validate_manifest(m, source="manifest"):
    f=[]
    if not isinstance(m,dict): return [Finding("INVALID_MANIFEST",f"{source}: root must be object")]
    for k in REQUIRED:
        if k not in m: f.append(Finding("MISSING_FIELD",f"{source}: missing '{k}'"))
    mid=m.get("id")
    if not isinstance(mid,str) or not ID_RE.match(mid): f.append(Finding("INVALID_MODULE_ID",f"{source}: invalid module id '{mid}'"))
    if m.get("schema_version") != 1: f.append(Finding("UNSUPPORTED_SCHEMA",f"{source}: schema_version must be 1"))
    ports=m.get("ports",{})
    for key in PORT_KEYS:
        if not isinstance(ports.get(key,[]),list): f.append(Finding("INVALID_PORT_LIST",f"{source}: ports.{key} must be array")); continue
        for p in ports.get(key,[]):
            if not isinstance(p,dict): f.append(Finding("INVALID_PORT",f"{source}: {key} entry must be object")); continue
            vals=[p.get("port")] if "port" in p else [p.get("start"),p.get("end")]
            if any(not isinstance(v,int) or v<1 or v>65535 for v in vals): f.append(Finding("INVALID_PORT",f"{source}: invalid {key} declaration {p}"))
            if "start" in p and isinstance(p.get("start"),int) and isinstance(p.get("end"),int) and p["start"]>p["end"]: f.append(Finding("INVALID_PORT_RANGE",f"{source}: start greater than end in {p}"))
    for op in m.get("lifecycle",[]):
        if op not in ALLOWED_LIFECYCLE: f.append(Finding("INVALID_LIFECYCLE",f"{source}: unsupported lifecycle operation '{op}'"))
    for svc in m.get("services",[]):
        if not isinstance(svc,dict) or not isinstance(svc.get("name"),str) or not svc["name"].endswith(".service"): f.append(Finding("INVALID_SERVICE",f"{source}: invalid service declaration {svc}"))
    for kind in ("config","data","legacy"):
        for p in m.get("paths",{}).get(kind,[]):
            if not isinstance(p,str) or not p.startswith("/") or ".." in Path(p).parts: f.append(Finding("INVALID_PATH",f"{source}: invalid absolute path '{p}'"))
    return f

def validate_directory(manifest_dir):
    reg=ModuleRegistry(manifest_dir).load(); findings=list(reg.findings)
    for mid,m in reg.modules.items(): findings += validate_manifest(m, f"{mid}.json")
    findings += reg.dependency_findings()+reg.dependency_cycles()+reg.conflict_findings()+reg.port_findings()
    return reg, findings

def load_schema(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))

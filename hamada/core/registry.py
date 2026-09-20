"""Read-only manifest, dependency, conflict and port registries."""
from dataclasses import dataclass
from pathlib import Path
import json

class RegistryError(ValueError): pass

@dataclass(frozen=True)
class Finding:
    code: str
    message: str
    severity: str = "ERROR"

class ModuleRegistry:
    def __init__(self, manifest_dir):
        self.manifest_dir = Path(manifest_dir)
        self.modules = {}
        self.findings = []

    def load(self):
        self.modules = {}; self.findings = []
        for path in sorted(self.manifest_dir.glob("*.json")):
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as exc:
                self.findings.append(Finding("INVALID_JSON", f"{path.name}: {exc}")); continue
            mid = data.get("id")
            if mid in self.modules:
                self.findings.append(Finding("DUPLICATE_MODULE_ID", f"duplicate module id '{mid}' in {path.name}")); continue
            self.modules[mid] = data
        return self

    def get(self, module_id): return self.modules.get(module_id)
    def list_ids(self): return sorted(x for x in self.modules if x)

    def dependency_findings(self):
        out=[]
        for mid, m in self.modules.items():
            for dep in m.get("dependencies", {}).get("modules", []):
                if dep not in self.modules: out.append(Finding("UNKNOWN_DEPENDENCY", f"{mid} depends on unknown module '{dep}'"))
            for dep in m.get("dependencies", {}).get("optional_modules", []):
                if dep not in self.modules: out.append(Finding("UNKNOWN_OPTIONAL_DEPENDENCY", f"{mid} references unknown optional module '{dep}'", "WARN"))
        return out

    def dependency_cycles(self):
        graph={m:set(v.get("dependencies",{}).get("modules",[])) & set(self.modules) for m,v in self.modules.items()}
        visiting=set(); visited=set(); out=[]
        def walk(node, trail):
            if node in visiting:
                cycle=trail[trail.index(node):]+[node]
                out.append(Finding("DEPENDENCY_CYCLE", " -> ".join(cycle))); return
            if node in visited: return
            visiting.add(node)
            for nxt in sorted(graph[node]): walk(nxt, trail+[nxt])
            visiting.remove(node); visited.add(node)
        for node in sorted(graph): walk(node,[node])
        unique={f.message:f for f in out}; return list(unique.values())

    def conflict_findings(self):
        out=[]
        for mid,m in self.modules.items():
            for other in m.get("conflicts",{}).get("modules",[]):
                if other in self.modules: out.append(Finding("DECLARED_MODULE_CONFLICT", f"{mid} conflicts with {other}", "WARN"))
        return out

    def port_findings(self):
        declarations=[]; out=[]
        for mid,m in self.modules.items():
            for scope in ("public","internal"):
                for proto in ("tcp","udp"):
                    for item in m.get("ports",{}).get(f"{scope}_{proto}",[]):
                        a=item["port"] if "port" in item else item["start"]
                        b=item.get("end",a)
                        declarations.append((proto,a,b,mid,scope,item.get("purpose","")))
        for i,left in enumerate(declarations):
            lp,la,lb,lm,ls,_=left
            for right in declarations[i+1:]:
                rp,ra,rb,rm,rs,_=right
                if lp != rp or lm == rm: continue
                lo=max(la,ra); hi=min(lb,rb)
                if lo <= hi:
                    span=str(lo) if lo==hi else f"{lo}-{hi}"
                    out.append(Finding("PORT_OWNERSHIP_CONFLICT", f"{lp.upper()} {span}: {lm}:{ls} overlaps {rm}:{rs}", "WARN"))
        return out

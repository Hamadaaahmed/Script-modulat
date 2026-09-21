import argparse, os, sys
from pathlib import Path
from hamada.modules.ssh.accounts import SSHAccountService
from hamada.modules.ssh.errors import SSHCoreError
from hamada.modules.openvpn.health import OpenVPNHealthService
from hamada.runtime.deployment import RuntimeDeployment, DeploymentError

EXIT_OK=0; EXIT_USER=2; EXIT_RUNTIME=20; EXIT_SYSTEM=30; EXIT_PARTIAL=40

def runtime_check(root: str) -> int:
    st=RuntimeDeployment(root).status()
    return EXIT_OK if st.healthy else EXIT_RUNTIME

def openvpn_health() -> int:
    items = OpenVPNHealthService().inspect()
    passed = 0

    for item in items:
        if item.ok:
            passed += 1
        print("{} {} {}".format(
            "PASS" if item.ok else "FAIL",
            item.name,
            item.detail,
        ))

    total = len(items)
    print("summary={}/{} passed".format(passed, total))

    if not items or passed != total:
        return EXIT_RUNTIME
    return EXIT_OK

def _pause():
    try: input("Press Enter to continue...")
    except EOFError: pass

def ssh_renew() -> int:
    svc=SSHAccountService()
    users=svc.list_accounts()
    os.system("clear") if sys.stdout.isatty() else None
    print("============================================")
    print("          HAMADA NET RENEW SSH ACCOUNT")
    print("============================================")
    if not users:
        print("No SSH accounts found."); print("============================================"); _pause(); return EXIT_OK
    rows=[]
    for i,u in enumerate(users,1):
        exp=svc.system.get_expiry(u); left=svc._days_left(exp,svc._today()); rows.append((u,exp,left))
        print(f"[{i:02d}] {u:<16} | Expire: {exp:<12} | Left: {left}d")
    print("[00] Back"); print("============================================")
    try: n=input("Select account number: ")
    except EOFError: return EXIT_USER
    if n in {"0","00"}: return EXIT_OK
    if not n.isdigit(): print("Invalid number"); return EXIT_USER
    idx=int(n)-1
    if idx < 0 or idx >= len(users): print("Invalid selection"); return EXIT_USER
    username,old_exp,left=rows[idx]
    print(f"Selected      : {username}"); print(f"Current Expiry: {old_exp}"); print(f"Days Left     : {left}")
    try: raw=input("Add days: ")
    except EOFError: return EXIT_USER
    if not raw.isdigit(): print("ERROR: days must be number"); return EXIT_USER
    # From this call onward mutation may have begun. Caller MUST NOT auto-fallback.
    try: result=svc.renew_account(username,int(raw))
    except SSHCoreError as exc:
        print(f"ERROR: renew failed; do not retry automatically: {exc}",file=sys.stderr); return EXIT_PARTIAL
    except Exception as exc:
        print(f"ERROR: renew may be partially applied; manual verification required: {exc}",file=sys.stderr); return EXIT_PARTIAL
    print("============================================")
    print(f"Renewed       : {username}"); print(f"Old Left Days : {result['left_days']}"); print(f"Added Days    : {result['added_days']}"); print(f"Total Days    : {result['total_days']}"); print(f"Expired On    : {result['expiry']}"); print("============================================"); _pause(); return EXIT_OK

def main(argv=None) -> int:
    ap=argparse.ArgumentParser(prog="hamada-runtime")
    ap.add_argument("command",choices=["runtime-check","runtime-status","openvpn-health","ssh-renew"])
    ap.add_argument("--root",default=os.environ.get("HAMADA_HOME","/opt/hamada"))
    ns=ap.parse_args(argv)
    if ns.command=="runtime-check": return runtime_check(ns.root)
    if ns.command=="openvpn-health": return openvpn_health()
    if ns.command=="runtime-status":
        st=RuntimeDeployment(ns.root).status(); print(f"root={st.root}"); print(f"active={st.active_version or '-'}"); print(f"previous={st.previous_version or '-'}"); print(f"healthy={'yes' if st.healthy else 'no'}"); return EXIT_OK if st.healthy else EXIT_RUNTIME
    return ssh_renew()

if __name__=="__main__":
    try: raise SystemExit(main())
    except DeploymentError as exc: print(f"ERROR: {exc}",file=sys.stderr); raise SystemExit(EXIT_RUNTIME)

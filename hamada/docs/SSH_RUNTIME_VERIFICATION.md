# Phase 2.5.1 live VPS verification plan

This is a plan only. Source tests do not constitute production verification.

## Pre-flight
Keep the current root/admin SSH session open; open and verify a second emergency session. Record project/version state and SHA-256 of `/usr/bin/renew-ssh`. Back up public SSH commands and `/etc/hamada/ssh-accounts`. Record current account expiries, `sshd -t`, SSH/Dropbear listening ports, relevant service state, free disk space, and `python3 --version`.

## Deployment
Stage and validate the Core release. Activate it, run runtime status/import checks, and verify that `/opt/hamada/legacy/renew-ssh` is executable, not world-writable, and byte-identical to `/opt/hamada/current/legacy/renew-ssh`. Only then install/activate the public `renew-ssh` wrapper. Do not restart SSH.

## Functional test
Use a dedicated disposable SSH account only. Record its original expiry, renew by a known number of days, and verify Linux `chage` expiry plus metadata `EXP_DATE`. Confirm `show-ssh` still presents the account, login works, payload files are byte-unchanged, SSH port remains 22, and Dropbear/WS/OpenVPN/SlowDNS/UDP Custom state is unchanged.

## Rollback consistency test
Before rollback, record `current`, `previous`, stable fallback SHA-256, and both release-local fallback SHA-256 values. Execute Runtime rollback. Verify:

- `current` resolves to the former `previous` release;
- `previous` resolves to the release that was active before rollback;
- `/opt/hamada/legacy/renew-ssh` matches the new active release-local `legacy/renew-ssh`;
- Runtime status is healthy;
- `state/runtime.json` records the same active/previous pair;
- account expiry/metadata did not change.

The Core pointer and stable fallback are separate filesystem objects and are not globally transactional. If rollback reports failure or the host/process is interrupted, do not assume success. Run Runtime status and compare the stable fallback with the active release-local fallback. A mismatch is unhealthy and requires reconciliation/manual verification before relying on fallback behavior.

Do not reverse a successful account renewal merely to test Runtime code rollback.

## Reboot/persistence
Only after basic checks pass, reboot the disposable/test VPS and verify `/opt/hamada/current`, `/opt/hamada/previous`, runtime status, public wrapper, and the matching stable Legacy fallback remain available.

## Phase 2.5.2 deploy/upgrade failure verification
For a future disposable/test VPS upgrade, record `current`, `previous`, stable fallback SHA-256, and `state/runtime.json` before deploy. If deploy reports failure, do not assume activation. Verify that the pre-deploy Core, fallback, pointers, and state were restored and that Runtime status is healthy. If the error states that automatic recovery was incomplete or manual verification is required, stop before using `renew-ssh` for mutation and inspect all four Runtime paths explicitly. The deployer does not claim global transactionality across these independent filesystem objects and Runtime status remains read-only.

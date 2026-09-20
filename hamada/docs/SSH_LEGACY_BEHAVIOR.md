# SSH Legacy Behavior Specification — Phase 2

## Scope map

`add-ssh` creates a Linux user with `useradd -M -s /bin/bash`, sets the password with `chpasswd`, sets account expiry using `chage -E`, writes `/etc/hamada/ssh-accounts/<user>.conf` mode 0600, creates SSH and OpenVPN WebSocket payload files, and prints mixed SSH/Dropbear/WS/TLS/Squid/OpenVPN/UDP Custom/SlowDNS connection information. Inputs are username/password/days; days must match digits and all fields must be non-empty. Duplicate Linux users are rejected by `id`. Username validity is delegated to `useradd`. The command pauses before exit.

`trial-ssh` accepts positive numeric minutes, generates `trial` + 2 random hex bytes and an 8-hex password, pipes username/password/1-day into `add-ssh`, appends `TRIAL_MINUTES`, `EXPIRE_TS`, and `EXPIRE_HUMAN`, then schedules a transient `systemd-run` unit that kills sessions, deletes the Linux user, and removes metadata after the requested minutes. Payload directories are not removed by that timer.

`renew-ssh` enumerates metadata files whose basename is also a current Linux user, sorts usernames, obtains expiry from `chage -l`, clamps negative/zero remaining days to zero, asks for numeric added days (zero is accepted), calculates `today + remaining + added`, applies `chage -E`, and replaces `EXP_DATE` in metadata only if the file exists. Selection is interactive and exit 0 is used for Back/no accounts.

`del-ssh` enumerates metadata-backed Linux users, displays `chage` expiry, asks for selection and `y/Y` confirmation, then best-effort `pkill -u`, best-effort `userdel`, and removes the metadata file. Legacy behavior reports Deleted even if `userdel` failed. Payload directories are not deleted.

`cek-ssh` reads username/password with grep/cut (not shell source), ignores metadata entries without a Linux user, uses `pgrep -u` and `ss -ntp` PID matching, and displays only accounts with at least one matching connection. It prints the saved password in the interactive status line.

`show-ssh` enumerates metadata-backed Linux users, uses `chage` for expiry, uses `EXPIRE_TS` for minute/hour trial countdown when present, counts sessions using `pgrep` + `ss`, then **sources the selected metadata file as shell** and prints mixed SSH/Dropbear/WS/TLS/Squid/OpenVPN/UDP Custom/SlowDNS information and payload URLs. This unsafe metadata sourcing is recorded; Phase 2's new core does not reproduce it, but `show-ssh` remains legacy to avoid changing its mixed presentation behavior before a dedicated compatibility cutover.

`menu-ssh` is an interactive dispatcher for add/trial/renew/delete/active/show and preserves menu numbering.

## Cross-module dependencies

The user-visible SSH commands expose or depend on Dropbear, Stunnel, WebSocket bridge routes, Squid, OpenVPN client files/payloads, UDP Custom credentials, and SlowDNS state. Those are presentation/compatibility dependencies, not SSH Core ownership.

## OpenSSH installer behavior

`install/modules/ssh/install.sh::configure_openssh` creates `/run/sshd`, detects old Port directives, stops/disables socket activation, removes Ubuntu socket requirement symlinks, temporarily stops Dropbear, backs up SSH config files if `.hamada.bak` is absent, comments existing Port/ListenAddress/PasswordAuthentication/PermitRootLogin directives, writes `/etc/ssh/sshd_config.d/99-hamada.conf` with Port 22/IPv4/password auth/root login/PAM, validates using `sshd -t`, enables/restarts SSH, and verifies port 22. The same installer also owns many out-of-scope services; Phase 2 does not rewrite or call this function from the new core.

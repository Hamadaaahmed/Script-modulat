# SSH compatibility — Phase 2.5

Public names remain `add-ssh`, `trial-ssh`, `renew-ssh`, `del-ssh`, `cek-ssh`, `show-ssh`, and `menu-ssh`.

`renew-ssh` is the only Phase 2.5 public cutover: the public shell wrapper preserves the interactive command name and delegates to the installed Core only after a non-mutating runtime preflight. If the Core is unavailable before mutation, it explicitly executes the version-controlled Legacy implementation deployed at `/opt/hamada/legacy/renew-ssh`. There is no automatic Legacy retry after the Core mutation boundary.

`add-ssh`, `trial-ssh`, `del-ssh`, `cek-ssh`, `show-ssh`, and the user-facing menu remain Legacy. `show-ssh` still has the known root `source` metadata risk; HN-013 remains only partially addressed.

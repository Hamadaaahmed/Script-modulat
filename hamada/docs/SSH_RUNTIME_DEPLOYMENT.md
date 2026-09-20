# SSH Core runtime deployment — Phase 2.5.1

## Source analysis
The canonical `setup.sh` obtains the project at `/root/commercial-vps-autoscript` by default, validates scripts, installs every `usr/bin/*` file into `/usr/bin`, then runs `scripts/bootstrap-full-install.sh`. `hamada-update` downloads a new source tree, validates `usr/bin`, backs up the existing source and `/usr/bin` targets, replaces the source tree, then overwrites `/usr/bin` commands. Before Phase 2.5 neither path deployed the Python `hamada/` package to an independent runtime location. `menu-ssh` still resolves the legacy menu from `${HAMADA_PROJECT_ROOT:-/root/commercial-vps-autoscript}`; that pre-existing dependency remains documented and is not part of the renew cutover.

## Runtime contract
`/opt/hamada` is used because Phase 1 already defines it as `HAMADA_HOME`, while `/etc/hamada` remains configuration/account state. Existing `/usr/local/lib/hamada` and `/usr/local/hamada` are service-specific legacy locations and are not expanded into the new Core contract.

Runtime layout:

    /opt/hamada/
      releases/<semantic-version>-<source-digest>/
        hamada/
        legacy/renew-ssh
        release.json
      current -> releases/<active>
      previous -> releases/<previous>
      legacy/renew-ssh
      state/runtime.json
      .deploy.lock

The source digest is deterministic and includes the deployed Legacy `renew-ssh` fallback as well as the Python Runtime subset. It is a content identity / accidental-corruption aid, not supply-chain authentication.

## Deployment lifecycle
The deployer copies to an isolated staging directory, validates required files, compiles Python source in memory, performs an isolated import test, rejects world-writable required files, requires an executable release-local `legacy/renew-ssh`, creates a checksum manifest, atomically renames staging to a release, installs the stable Legacy fallback with a temporary-file plus atomic replace, switches `previous`/`current`, verifies that the stable fallback matches the active release, then writes deployment state atomically. `flock` prevents concurrent deployments.

A successful deployment therefore ends with both `/opt/hamada/current` and `/opt/hamada/legacy/renew-ssh` corresponding to the same release. Runtime status treats a Core/fallback mismatch, missing/invalid deployment state, or state that disagrees with the active/previous pointers as unhealthy.

A public wrapper never depends on the source checkout. It resolves `/opt/hamada/current` and uses `PYTHONPATH` only for that installed release.

## Rollback consistency — Phase 2.5.1
Rollback treats the active Core release and stable Legacy fallback as a coordinated Runtime set.

Before any rollback mutation it:

1. resolves and validates `previous` inside the controlled Runtime root;
2. validates the complete target release against its existing `release.json` checksum model;
3. requires a non-world-writable executable target `legacy/renew-ssh`;
4. prepares and verifies a temporary stable-fallback replacement;
5. snapshots the existing stable fallback for in-process recovery.

Rollback then replaces the stable fallback atomically, atomically switches `current`, updates `previous` to the release being left, verifies Core/fallback consistency, and only then writes `state/runtime.json`.

The fallback path and `current` symlink are two independent filesystem objects, so the operation is **not** claimed to be one global filesystem transaction. Each individual replacement is atomic, but a process/host crash can occur between replacements. The ordering minimizes the window, all target content is validated before mutation, and `status()` detects a surviving Core/fallback mismatch as unhealthy. Re-running rollback can reconcile the common pre-pointer crash state because the release-local fallback remains immutable and versioned.

For caught failures after mutation begins, rollback attempts to restore the exact pre-rollback stable fallback and the original `current`/`previous` pointers before returning an error. If any recovery step also fails, the deployer reports that manual verification is required; it does not report success and it does not write a successful rollback state.

Rollback changes Runtime code selection only. It does not alter Linux users, passwords, expiries, `/etc/hamada/ssh-accounts`, payloads, SSH configuration, ports, firewall, or services.

## Rollback and retention
The current and previous known-good releases are retained. No aggressive release pruning is implemented. Release-local Legacy fallbacks are part of release integrity and are never fetched dynamically.

## Installer/updater integration
`setup.sh` deploys Core before installing `/usr/bin` wrappers. `bootstrap-full-install.sh` also performs the same idempotent deployment so its direct supported use does not omit Core. `hamada-update` activates the new source, deploys/validates Core, then installs wrappers. If later update verification fails, updater invokes the Runtime rollback command; Phase 2.5.1 rollback now restores both the previous Core and its matching stable Legacy fallback before the old source/commands are restored.

## Fallback / mutation safety
`renew-ssh` falls back to `/opt/hamada/legacy/renew-ssh` only when Core is unavailable or fails preflight, before mutation begins. Once the Core `ssh-renew` entrypoint is executed, no fallback is attempted. A Core error after `chage` can therefore require manual inspection but cannot automatically double-renew the account.

## Existing users
Linux users plus `/etc/hamada/ssh-accounts` remain authoritative. No user/account migration is required.

## Python compatibility
The deployable runtime subset is deliberately limited to `hamada/modules/ssh` plus `hamada/runtime`, `hamada/__init__.py`, and `hamada/VERSION`. It avoids pulling the development Foundation into the runtime contract. Runtime-relevant Python source is grammar-checked against Python 3.6 syntax because the existing installer declares Ubuntu 18 as supported; no third-party packages or virtualenv are required. This source-level grammar check is not a substitute for live testing on every supported Ubuntu release.

## Deploy/upgrade consistency — Phase 2.5.2
Normal deploy/upgrade now uses the same coordinated-recovery principle as rollback. Before the first authoritative Runtime mutation, the new release and its release-local Legacy fallback are validated, the stable replacement is prepared, and the pre-deploy `current`, `previous`, stable fallback, and `state/runtime.json` are captured.

Deployment still uses separate atomic replacements for the stable fallback, `previous`, `current`, and `runtime.json`; these independent paths are **not** one global filesystem transaction. If a caught failure occurs after mutation begins, deploy attempts to restore the pre-deploy fallback, `current`, `previous`, and runtime state. A successfully restored upgrade remains healthy and the deploy still returns an error. If any recovery step fails, deployment raises an explicit manual-verification error and never reports success. First-install recovery restores the authoritative paths to their pre-install absence where safely possible; an inactive validated release directory may remain available for a later retry.

The outer updater sets `CORE_DEPLOYED=1` only after the Runtime deploy command returns successfully. Therefore a deploy failure that self-recovers does not trigger the updater's later-stage Runtime rollback path. The updater rollback remains reserved for failures that happen after a Core deployment completed successfully.

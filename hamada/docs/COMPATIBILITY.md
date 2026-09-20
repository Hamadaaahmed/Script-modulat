# Compatibility Policy
All existing public commands and behaviors are compatibility surface, including `menu`, account commands such as `add-ssh`/`show-ssh`, `xrayctl`, `hamada-update`, settings, status/doctor, reset/restore/uninstall and every other currently shipped `/usr/bin` entry point.

Phase 1 does not modify them. In later phases, an old public name remains a compatibility wrapper unless removal is explicitly approved. Legacy account stores, paths, ports and config formats remain supported until an explicit migration contract says otherwise.

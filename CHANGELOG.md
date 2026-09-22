# Changelog

## Unreleased – 2026-09-22

- Fixed: `build-essential` and `locate` ran the package manager without a package
  name (`apt-get install -y`) and reported success. They now name the package for
  each distribution; locate on openSUSE and Alpine stops with a clear message.
- Fixed: as root without sudo (Proxmox VE, LXC, containers) 79 of 96 scripts
  failed, as a normal user with sudo 17. The menu and `bootstrap.sh` now run
  root commands directly as root and with sudo otherwise (`as_root`, `$SUDO`);
  without both there is a clear message. Tested: 84 of 96 run both as root and
  as a normal user, the rest needs network or Docker in the test.
- Fixed: entries meant for one distribution (`os_only: ubuntu`) showed up on
  every one - a single value was only read as a list. The Proxmox entry (guest
  agent) stays visible everywhere, PiKVM counts as `arch` and `archarm`.
- New folder layout following the project standard: the program is in
  `apps/cli/` (start: `bash ~/ulh/apps/cli/ulh.sh`), the installer in
  `tools/install.sh`, the documentation in `docs/`.
- New paths: catalog `apps/cli/assets/catalog.yaml` (was `config.yaml`), scripts
  `apps/cli/assets/scripts/` (was `scripts/`), libraries `apps/cli/classes/` (was
  `lib/`), yq `apps/cli/vendor/yq/`, script template
  `apps/cli/templates/script-template.sh`.
- Your own files now live in `apps/cli/config/` (`repo.yaml`, `answer.yaml`) and
  `apps/cli/data/` (`keys/`, `repos/<path>/`). On its first start ulh moves them
  there from the old `custom/` folder - nothing is overwritten or deleted. Scripts
  in your repositories that load `../../../lib/bootstrap.sh` keep working.
- Old commands keep working: `cd ~/ulh && bash ulh.sh` and the published one-liner
  with `.../main/install.sh` forward to the new places. `custom/repo.yaml` and
  `custom/demo-scripts/scripts/file-backup.sh` stay in git unchanged for now, so
  `git pull` of old installations never stops at them; ulh cleans them up locally.
- New one-liner: `wget -qO - https://raw.githubusercontent.com/sorglos-it/ulh/main/tools/install.sh | bash`.
  The installer only installs git when it is missing.
- Fixed: 48 scripts stopped at their first line (`msg_info: command not found`)
  and installed nothing.
- Fixed: SSH keys, tokens and basic auth of custom repositories were never used.
- Fixed: the auto-update of cloned custom repositories failed once ulh had run one
  of their scripts (file mode change). ulh no longer changes file modes.
- Fixed: the restart after a self-update failed when ulh was started as
  `bash ulh.sh`, and `--check-update` always said "You are up to date."
- New: `--help`, tests (`bash apps/cli/tests/run.sh`), `docs/scripts.md` generated
  from the catalog (`bash tools/gen-scripts-doc.sh`).

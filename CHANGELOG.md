# Changelog

## Unreleased – 2026-09-22

- New: `ngc-controller` sets up the controller of a NextGenCloud installation,
  which runs on every server of one (new category NextGenCloud, Debian and
  Ubuntu, `sudo`): the program `ngc-controller` in `/usr/lib/ngc/`, taken only
  from a release whose signature and checksum fit and never older than the one
  installed, `/etc/ngc/controller.json` (root, 0600) with the roles of this
  server and, with the role `db`, the access for the migrations of an update,
  the service `ngc-controller.service`, and podman from the package sources
  where the server carries services. The key of the server and the pairing are
  the program's own work: the script hands `ngc-controller pair` the pairing
  code through its standard input, never in a command line, and shows what the
  program printed - the fingerprint of this server's key and the anchor out of
  the code, to compare with NextGenCloud. `install`, `configure` and
  `uninstall`; a second run of `install` pairs nothing again and keeps the key
  the data of every app is encrypted with, so the service is restarted only
  when something really changed. Its menu entry, its three actions and all
  eight questions are in the catalog in five languages; what the script itself
  prints is English, as in every other script. The program file comes from a
  release of NGC, or from `/var/lib/ngc/staged` when a `release.json` lies
  there - and until NGC publishes its first release, that second way is the
  only one that works.
- New: `apps/cli/tests/ngc-controller.test.sh` runs the parts of
  `ngc-controller` that work without a server: `controller.json` and the
  service file it writes, byte for byte, which names, addresses, roles,
  passwords and pairing codes it refuses, and that a change of the roles leaves
  the keys of the server alone. The cases that ask about the answers need
  `openssl` and the ones about a change of the roles need `jq`; that each is
  there is a check of its own instead of a quiet skip.
- New: `ngc-api` sets up the API server of a NextGenCloud installation (new
  category NextGenCloud, Debian and Ubuntu, `sudo`): the programs `ngc-api` and
  `ngc-store` in `/usr/lib/ngc/`, taken only from a release whose signature and
  checksum fit and never older than the one installed, the keys of this node,
  `/etc/ngc/api.json` (root, 0600), the service `ngc-api.service`, and at the end
  the fingerprint of the TLS key every other part checks this server by plus, on
  the first API server, the setup code of the first admin account. With a join
  code it takes the two shared keys of a running installation (`secretKey` and
  `challengeKey`) instead of its own. `install`, `configure` and `uninstall`; a
  second run of `install` keeps the keys that are there and changes nothing that
  is already right, so the service is restarted only when something really
  changed. Its menu entry, its three actions and all eleven questions are in the
  catalog in five languages; what the script itself prints is English, as in
  every other script. The program files come from a release of NGC, or from
  `/var/lib/ngc/staged` when a `release.json` lies there - and until NGC
  publishes its first release, that second way is the only one that works.
- New: `apps/cli/tests/ngc-api.test.sh` runs the parts of `ngc-api` that work
  without a server: `api.json` and the service file it writes, byte for byte,
  and which names, addresses, keys, passwords, CA files and join codes it
  refuses. The cases that ask about the answers need `openssl`, and that it is
  there is a check of its own instead of a quiet skip.
- New: five languages - English, German, French, Italian and Spanish. The menu,
  the messages and the descriptions and questions of all 96 scripts. ulh starts in
  the language of the system; the key `l` switches and remembers it
  (`apps/cli/config/settings.yaml`), `--lang de` works for one start. Yes/no
  answers count in every language (y, j, o, s = yes). What the scripts themselves
  print stays English.
- Catalog: the translations sit right below the English text (`descriptionDE`,
  `questionFR`, category names `nameIT` ...). Custom repositories can do the same
  in their `config.yaml`. The tests fail when a translation is missing.
- The search also finds the English words when another language is shown.
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

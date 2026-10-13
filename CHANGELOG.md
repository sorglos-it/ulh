# Changelog

## Unreleased – 2026-09-22

- New: `ngc-all` sets up a whole NextGenCloud on ONE machine, a Raspberry Pi
  among them (category NextGenCloud, Debian and Ubuntu, `sudo`). It is the way
  in for a small installation, and it was the one that was missing: `ngc-api`
  refuses every database driver but MariaDB and says in its own message that a
  single machine with SQLite is this script's business. Here the database is a
  FILE, encrypted whole with AES-256-XTS and a key of 64 bytes, so no database
  server, no account, no password and no CA is asked for at all - `config.DB`
  of NGC refuses all four next to a SQLite path. `install` puts `ngc-api`,
  `ngc-store` and `ngc-controller` into `/usr/lib/ngc/` out of a release whose
  signature and checksum fit and never older than the one installed, writes
  `/etc/ngc/api.json` (root, 0600), starts `ngc-api.service` and shows the
  fingerprint of this machine and the setup code for the first admin account.
  `configure` with a pairing code out of the web interface pairs the controller
  of this machine itself, writes `/etc/ngc/controller.json` with all four roles
  and starts `ngc-controller.service`; the pairing runs on a provisional
  configuration in a folder of `mktemp -d` that never reaches `/etc/ngc`, and
  the script checks afterwards that the file the program wrote names a real API
  before it puts it in place. `uninstall` asks whether the configuration, the
  keys and the data go or stay under `/var/lib/ngc/`. A second run of `install`
  pairs nothing again and keeps every key: on one machine there is no second
  copy of any of them, so a fresh one would leave the whole installation
  unreadable.
- New: the two programs of this machine get two separate database files with
  two separate keys - the API `/var/lib/ngc/api/ngc.db`, the controller
  `/var/lib/ngc/controller/state.db` - and the script refuses to write anything
  if those two are ever set to the same path. The reason is measured and not
  assumed: on SQLite every program migrates at its own start, and the migration
  lock only holds for the moment of a migration, so it does not keep two
  programs apart. Where one file really does have two readers - the controller
  carries the access for the migrations of an update, and on this machine that
  is the API's file - `ngc-controller.service` is ordered after
  `ngc-api.service`, so exactly one of the two migrates first, and both carry
  `Restart=on-failure` with `RestartSec=5`, so whoever meets the lock comes back
  a few seconds later instead of forcing its way in.
- New: `apps/cli/tests/ngc-all.test.sh` runs the parts of `ngc-all` that work
  without a machine: `api.json` and `controller.json` byte for byte, both
  service files, the two separate database files and the guard over them, the
  64 byte key against the 32 byte one, the provisional configuration of the
  pairing, and which names, addresses, keys and pairing codes the script
  refuses. The functions are read out of the shipped script itself, so this
  measures the file that is installed. One case needs `jq` and is RED on a
  machine without it instead of skipping itself quietly.
- Known hole, named rather than half built: `ngc-all` does not set up the web
  interface. Apache, PHP, the certificate and `/etc/ngc/web.json` are
  `ngc-web`'s work, and `ngc-all` prints the fingerprint that script asks for
  and names it as the next step.
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

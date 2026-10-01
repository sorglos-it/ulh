# Changelog

## Unreleased – 2026-09-22

- New: `ngc-web` sets up the web interface of a NextGenCloud installation
  (new category NextGenCloud, Debian and Ubuntu, `sudo`): Apache and PHP from
  the package sources, the interface in `/var/www/ngc/` with only its `public/`
  reachable from outside, the certificate from Let's Encrypt, self-signed or
  imported, the certificate of every API server checked against the fingerprint
  the admin typed, and Apache's balancer for `/api/`. `install`, `configure` and
  `uninstall`; a second run of `install` changes nothing that is already right,
  and Apache is reloaded only after `apachectl configtest`. Its menu entry, its
  three actions and all six questions are in the catalog in five languages; what
  the script itself prints is English, as in every other script. The program
  files come from a release of NGC, or from `/var/lib/ngc/staged` when a
  `release.json` lies there - and until NGC publishes its first release, that
  second way is the only one that works.
- `ngc-web`: the files Apache hands out itself - every `.js`, `.css` and the
  vendored code below `/assets/` - now carry four protective headers of their
  own (`X-Content-Type-Options`, `Cross-Origin-Resource-Policy`, a
  `Content-Security-Policy` written for a file and not for a page, and
  `Strict-Transport-Security`). No PHP of the interface ever sees those answers,
  so nothing else could have set them. The routing is `FallbackResource` instead
  of a rewrite that took `/assets/` out of itself: a missing file there used to
  be answered by Apache alone, with no header at all, and now reaches the single
  entry point, which answers 404 with every header the interface sends.
  Everything beside `public/` is denied a second time, `.htaccess` and symbolic
  links are off, and `ServerSignature` is off. The same four headers stand once
  more in the NGC repository (`apps/web/templates/apache-vhost.conf`); `ngc-web`
  compares the two on a server that has both and says so when they differ.
  A virtual host somebody wrote by hand is kept as
  `ngc-web.conf.before-ulh` before it is replaced, instead of vanishing.
- New: `apps/cli/tests/ngc-web.test.sh` runs the parts of `ngc-web` that work
  without a server: the balancer it writes for Apache byte for byte, `web.json`,
  the four protective headers of the virtual host and its routing, and which
  host names, addresses and fingerprints it refuses.
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

# Changelog

## Unreleased – 2026-09-22

- The five NextGenCloud scripts were written on five branches and are now one
  set: `ngc-all`, `ngc-api`, `ngc-controller`, `ngc-db` and `ngc-web`, the
  category `NextGenCloud` in all five languages, 101 scripts in 17 categories.
  Measured before anything was moved: `ngc-api.sh` and `ngc-controller.sh` were
  byte for byte the same file on all three branches that carried them, and
  `ngc-web.sh` had two versions, not three - the newer one takes the virtual
  host out of NGC's release, and that is the one that is here. Every branch sat
  directly on `main`, so nothing had to be guessed about an order.
- New: `apps/cli/tests/ngc-shared.test.sh`, 18 cases for what holds ACROSS the
  five scripts and what no single-script file can hold: that the host check
  every one of them carries as its own copy is byte for byte the same copy in
  all five AND gives the verdicts of `shared/testdata/ulh/host.sh` for 24 hosts,
  that no script puts a pairing or join code or a password into a message, that
  none of them switches a certificate check off, that each sets `LC_ALL=C`
  above its host check, and that the last message of `ngc-all` really hands the
  one machine case over to `ngc-web` with the address and the fingerprint - the
  only thing that carries an admin from the one script to the other. Nine
  changes to the scripts were each measured to make one of those cases red, and
  a rename of a local variable in all five was measured to leave the whole run
  green.
- Fixed: `ngc-api` printed the join code itself in its error message ("This is
  no join code: '<the code>'"). `ngc-controller` and `ngc-all` never did; a code
  is good exactly once, and whatever a `log_*` line prints ends up in a
  terminal, in a scroll and in whatever somebody pastes into an issue. The
  message now names the code without showing it.
- Fixed in the tests: six cases of `ngc-web.test.sh` carried a `> /dev/null` on
  the `check` call itself instead of on the command, so they ran and were
  counted but their result line never reached the log - 639 counted against 633
  printed in every run. `check` already throws the command's output away, so the
  redirection is gone. The count of that file, 200, was right all along; what
  was wrong was that six of its results could not be read.
- A comment of `ngc-web` named `apps/web/templates/apache-apis.conf.example` in
  the NGC repository as the source of the balancer file; that path does not
  exist. The form is in `shared/ulh.md`, and the repository holds it twice: as
  the controller's template and as the bytes
  `TestBalancerTemplateMatchesTheContract` expects. Measured on 15.10.2026 the
  script, the contract and that test data are byte for byte the same file.
- Measured, and it is the answer to "can a small installation be set up today":
  not yet, and not because of ulh. `ngc-web` takes its virtual host out of
  NGC's release (`templates/apache-vhost.conf`), and the NGC repository does not
  carry it: `apps/web/` holds nothing but `CLAUDE.md` and `VERSION`, so the web
  interface is not written and no release of it exists. `ngc-web` stops with a
  message that names the file instead of writing a web root nobody set up, which
  is what it is meant to do. Every path the five scripts name in the NGC
  repository was checked on 15.10.2026; this is the only one that is not there.
- Still open, and it is a question for NGC and not for ulh: `shared/ulh.md`
  gives `ngc-all` the answer `cert_mode` and says its `web.json` gets the local
  API by itself. `ngc-all` does neither, on purpose - a second virtual host,
  certificate and balancer in ulh would be a second place to keep right, and
  the balancer form is a contract one side must not copy. So a small
  installation needs `ngc-all` and then `ngc-web`, and `ngc-all` says so with
  the address and the fingerprint. Either the contract says that, or `ngc-all`
  grows the web half; `shared/` is the coordinator's to change.
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
- New: `ngc-db` - the database of a NextGenCloud installation. MariaDB with
  Galera, TLS 1.3 against the CA of the installation for clients and for the
  replication, and MariaDB's own encryption at rest (AES-256 through
  file_key_management). The first server makes the CA and prints its
  certificate; every other server makes its own key, shows only its request,
  and gets the certificate with the action `sign` on the first server - a
  private key never leaves its machine. Actions: install, configure, sign,
  uninstall, backup, restore. `backup` writes one encrypted file of the
  database plus its sha256 (AES-256-CBC, PBKDF2 with 600000 rounds); the
  passphrase is asked on the terminal without echo and never becomes an answer,
  and no password ever stands on a command line - the server is reached as root
  over the unix socket. `restore` checks the checksum and the content before it
  says, in the admin's language, that the whole cluster is replaced and not
  just this server, and it does nothing without an explicit yes. It never
  drops `ngc`: the dump goes into a database of its own, and only when it
  loaded and brought tables with it do the names move, table by table with
  `RENAME TABLE` (MariaDB has no `RENAME DATABASE`). What was in `ngc` is kept
  under `ngc_before_<stamp>` and removed by a human, never by the script - so
  there is no moment in which the old data are gone and the new ones not there.
  The price, and it is named: room for both states until someone drops the old
  one.
  New category `NextGenCloud` in the catalog, in all five languages.
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
  links are off, and `ServerSignature` is off.
  A virtual host somebody wrote by hand is kept as
  `ngc-web.conf.before-ulh` before it is replaced, instead of vanishing.
- `ngc-web` no longer writes a virtual host of its own: it takes the one NGC
  ships with its release (`templates/apache-vhost.conf`, unpacked to
  `/var/www/ngc/templates/apache-vhost.conf`), fills in the name of this server
  and writes that. So there is one version of those settings and not two, and a
  change NGC makes to a header reaches every machine with the next release.
  Before anything is written the file is held against what this version of
  `ngc-web` expects - the four protective headers, the paths of this setup, and
  the name left open twice; a release that fails any of it is refused by name
  and nothing is changed, so a server that runs keeps the virtual host it has.
  A release too old to carry the file cannot be set up and says so.
- New: `apps/cli/tests/ngc-web.test.sh` runs the parts of `ngc-web` that work
  without a server: the balancer it writes for Apache byte for byte, `web.json`,
  the four protective headers of the virtual host and its routing, and which
  host names, addresses and fingerprints it refuses.
- `ngc-web`: that test grew from 51 checks to 200. What it promised in its own
  comments and nothing held it to is measured now: safe unpacking of a release
  (an absolute path, a `..`, a link or a missing `public/index.php` is refused,
  and a refused archive leaves the interface that is there alone), the strict
  base64url of `enc.B64` down to a second spelling of the same bytes, `put_file`
  (the mode it was given, root as the owner of the file before the rename, and
  nothing written when the bytes already match, which is what makes a second
  run of `install` change nothing), the certificate for the browser with real
  `openssl` (397 days, `IP:` for an address and `DNS:` for a name, the key
  0600, a key that belongs to another certificate and a key with a password
  both refused), `pin_of_cert` (never the SHA-256 of nothing), `ngc-md.conf`,
  the fact that `mod_md` is switched on in the Let's Encrypt mode and in no
  other, the options `download` may not lose, and `uninstall` with and without
  purge - where what counts most is what it must NOT take: `api.json` and
  `controller.json` of other parts on the same server, `release.seq`, and a
  virtual host somebody wrote by hand. Each of those was held against a change
  to the script that breaks it, and two changes that break nothing were checked
  to leave the test green.
- `ngc-web`: measured while writing those cases, and worth writing down: a
  second spelling of the same bytes in base64url (`aGl` for `aGk`) is refused
  by GNU coreutils' `base64 -d` itself, before `b64url`'s own re-encode check
  can see it. Taking that check out of the script leaves every case green, so
  on this kind of machine the line is untested - it earns its keep on a
  `base64` that is more forgiving, busybox among them. The test says so out
  loud instead of claiming the line.
- `ngc-web`: four cases around the release (`release_payload`, `release_file`,
  `verify_release` and the refusal of an older release) and `shellcheck` need
  `jq` or `shellcheck`, which the machine this was written on has neither of.
  They are RED and say `NOT MEASURED` instead of skipping themselves: a case
  that steps over a missing tool is the worst kind of green. `sync_api_trust`,
  `fetch_cert`, `ensure_php`, `ensure_packages` and `apache_apply` need a
  Debian with Apache and an API answering on a port; they are measured on the
  server and nothing here pretends otherwise.
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

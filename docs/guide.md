# ulh Documentation

Complete guide to ulh v0.5 architecture, configuration, and development.

**96 scripts across 16 categories** | Multi-distro support | Per-action automation

## Table of Contents

1. [Architecture](#architecture)
2. [Installation](#installation)
3. [Catalog](#catalog)
4. [Answer File (answer.yaml)](#answer-file-answeryaml)
5. [Custom Repositories](#custom-repositories)
6. [Script Development](#script-development)
7. [Menu System](#menu-system)
8. [Troubleshooting](#troubleshooting)
9. [API Reference](#api-reference)

---

## Architecture

### Design Philosophy

ulh prioritizes simplicity, consistency, and maintainability:

- **Single Entry Point** - `apps/cli/ulh.sh` orchestrates everything
- **Focused Libraries** - Each file in `classes/` handles one responsibility
- **Explicit Parameters** - Comma-separated strings, no silent globals
- **Cross-Platform** - All scripts work on 5+ distribution families
- **Auto-Updating** - Transparent self-updates with `exec` restart
- **Your files stay yours** - `config/` and `data/` are never touched by updates

### File Structure

```
ulh/                              # clone target, default: ~/ulh
├── ulh.sh                        # old start command, forwards to apps/cli/ulh.sh
├── install.sh                    # old one-liner target, forwards to tools/install.sh
├── apps/cli/                     # the program
│   ├── ulh.sh                    # entry point: auto-update, your files, menu
│   ├── VERSION                   # version shown in the menu header
│   ├── classes/                  # framework (sourced, never called directly)
│   │   ├── bootstrap.sh          # sourced BY the scripts: parse_parameters, log_*, msg_*, detect_os
│   │   ├── colors.sh             # ANSI colors (single source of truth)
│   │   ├── core.sh               # msg_* helpers, OS detection for the menu
│   │   ├── execute.sh            # prompts, answer.yaml/autoscript, runs the script
│   │   ├── menu.sh               # menu rendering + navigation loops
│   │   ├── repos.sh              # custom repo clone/pull/auth
│   │   ├── update.sh             # self-update via git
│   │   ├── userdata.sh           # config/ and data/, takes over the old custom/ folder
│   │   └── yaml.sh               # yq wrappers (yaml_scripts, yaml_action_name, ...)
│   ├── assets/
│   │   ├── catalog.yaml          # menu + action definitions for ALL system scripts
│   │   └── scripts/<name>.sh     # one file per program - THE place to look
│   ├── templates/
│   │   ├── script-template.sh    # copy this to start a new script
│   │   └── demo-*                # the demo repository, copied to data/ on first start
│   ├── config/                   # YOUR settings (git-ignored, only *.example in git)
│   │   ├── repo.yaml.example     # template for repo.yaml
│   │   ├── repo.yaml             # your custom repositories
│   │   └── answer.yaml           # prompt defaults + autoscript flags (optional)
│   ├── data/                     # YOUR runtime data (git-ignored)
│   │   ├── keys/                 # SSH keys for private repos
│   │   ├── repos/<path>/         # custom repos (own config.yaml + scripts/)
│   │   └── lib/                  # generated, see Custom Repositories
│   ├── vendor/yq/                # bundled yq binaries (amd64, arm64, arm, 386)
│   └── tests/                    # run.sh + tests, manual test scripts
├── tools/
│   ├── install.sh                # installer (installs git if missing, clones/pulls ulh)
│   └── gen-scripts-doc.sh        # writes docs/scripts.md from the catalog
├── docs/
│   ├── guide.md                  # this file
│   ├── scripts.md                # all scripts: actions, sudo, distros (generated)
│   └── backstory.md              # how the name happened
├── README.md, CHANGELOG.md, LICENSE, THIRD-PARTY.md
└── custom/                       # only in old installations - moved on first start
```

**Looking for a specific script?** [scripts.md](scripts.md) lists every script with
its actions, sudo requirement and supported distributions.

### Where To Look For What

| I want to ... | Look at |
|---------------|---------|
| find a script while ulh is running | press `s` in the menu, or type `/term` at the prompt |
| find the code for program `X` | `apps/cli/assets/scripts/X.sh` |
| change menu entry, category or prompts of `X` | `apps/cli/assets/catalog.yaml` -> `scripts.X` |
| add a new program | `cp apps/cli/templates/script-template.sh apps/cli/assets/scripts/X.sh` + entry in the catalog |
| run something without the menu | `sudo bash apps/cli/assets/scripts/X.sh "install"` |
| see which actions `X` has | `bash apps/cli/assets/scripts/X.sh` (prints usage from the catalog) |
| preset answers / automate | `apps/cli/config/answer.yaml` |
| change how prompts behave | `apps/cli/classes/execute.sh` |
| change the menu layout | `apps/cli/classes/menu.sh` |
| add your own script repo | `apps/cli/config/repo.yaml` + `apps/cli/classes/repos.sh` |

**Grep cheat sheet** (run from the ulh directory):

```bash
ls apps/cli/assets/scripts | grep -i spool                           # find a script file
grep -n "^  spoolman:" -A 20 apps/cli/assets/catalog.yaml           # its catalog block
grep -n "description:" apps/cli/assets/catalog.yaml | grep -i vnc   # search all descriptions
```

### Execution Flow

1. `ulh.sh` starts → sets UTF-8 locale, loads the libraries from `classes/`
2. Auto-update check → git fetch + pull (if updates exist, `exec` restart)
3. Your files → moves an old `custom/` folder once, creates missing files in `config/` and `data/`
4. Load the catalog → `assets/catalog.yaml`
5. Initialize repositories → clone/sync custom repos
6. Show menu → repository selector or ulh scripts directly
7. Execute action → call script with parameters
8. Return to menu

**Call chain of one action:**

```
ulh.sh -> menu.sh (pick script + action, or search with s / /term)
       -> execute.sh (prompts, answer.yaml, sudo)
       -> assets/scripts/<name>.sh "action,VAR1=val1,VAR2=val2"
          -> classes/bootstrap.sh (parse_parameters, detect_os, logging)
```

### Runtime Paths

| Path | What |
|------|------|
| `~/ulh/` | default install location (`tools/install.sh` clones here) |
| `~/ulh/apps/cli/config/repo.yaml` | your custom repositories, never overwritten by updates |
| `~/ulh/apps/cli/config/answer.yaml` | your prompt defaults, never overwritten by updates |
| `~/ulh/apps/cli/data/keys/` | SSH keys for private custom repos (`chmod 600`) |
| `~/ulh/apps/cli/data/repos/<path>/` | custom repo with its own `config.yaml` and `scripts/` |
| `~/ulh/apps/cli/vendor/yq/yq-<arch>` | bundled yq, picked automatically by architecture |

Everything ulh itself needs lives under the clone directory - there is no state
in `/etc` or `/var`. What the individual scripts install (packages, services,
config files) is documented in the header comment of each script.

**Installations from before 2026-09-22** kept these files in `custom/`
(`custom/repo.yaml`, `custom/answer.yaml`, `custom/keys/`, `custom/<repo>/`).
ulh moves them to the places above on its first start after the update. Nothing
is overwritten: if a file already exists in the new place, the old one stays and
ulh says so.

---

## Installation

### Automatic (One-liner wget)

```bash
wget -qO - https://raw.githubusercontent.com/sorglos-it/ulh/main/tools/install.sh | bash
```

### Automatic (One-liner curl)
```bash
curl -sSL https://raw.githubusercontent.com/sorglos-it/ulh/main/tools/install.sh | bash
```

Then:
```bash
bash ~/ulh/apps/cli/ulh.sh
```

The older one-liner with `.../main/install.sh | bash && cd ~/ulh && bash ulh.sh`
still works: both files in the root forward to the new places.

### Manual Clone

```bash
git clone https://github.com/sorglos-it/ulh.git
bash ulh/apps/cli/ulh.sh
```

### Platform-Specific

**tools/install.sh** automatically:
- Installs git if it is missing (the only dependency) - detects the OS
  (Debian, Red Hat, Arch, SUSE, Alpine) for that
- Clones ulh to `~/ulh`, or pulls the latest version if it is already there
- Works with or without sudo (detects if running as root)

---

## Catalog

`apps/cli/assets/catalog.yaml` controls the built-in ulh scripts. Updates replace
it - put your own scripts into a [custom repository](#custom-repositories).

```yaml
scripts:
  curl:
    description: "HTTP requests utility"
    category: "Essential Tools"
    file: "curl.sh"
    os_family:
      - debian
      - redhat
      - arch
      - suse
      - alpine
    
    actions:
      - name: "install"
        parameter: "install"
        description: "Install curl"
        prompts: []
      
      - name: "update"
        parameter: "update"
        description: "Update curl"
        prompts: []
      
      - name: "uninstall"
        parameter: "uninstall"
        description: "Uninstall curl"
        prompts: []

  mariadb:
    description: "MariaDB database server"
    category: "Databases"
    file: "mariadb.sh"
    sudo:
    os_family:
      - debian
      - redhat
    
    actions:
      - name: "install"
        parameter: "install"
        description: "Install MariaDB"
        prompts:
          - question: "Root password?"
            variable: "ROOT_PASSWORD"
            type: "text"
            default: ""
```

**Fields:**
- `category` - Shown in menu
- `description` - Brief info
- `file` - Script file in `apps/cli/assets/scripts/`
- `sudo:` - Elevate with sudo (presence-based, optional)
- `os_family` - Supported distributions (optional)
- `os_only` - Single distro (optional, overrides os_family)
- `os_exclude` - Blacklist distros (optional)

**Prompt Types:**
- `text` - Free input
- `yes/no` - Boolean
- `number` - Numeric input

After changing the catalog, refresh the script reference: `bash tools/gen-scripts-doc.sh`.

---

## Answer File (answer.yaml)

### What It Does

The `apps/cli/config/answer.yaml` file provides **default values for prompts** and enables **per-action automation** via the `autoscript` flag.

**Two modes:**
1. **Interactive mode** (default) - User sees all prompts, can press ENTER for defaults
2. **Autoscript mode** - Prompts skipped, script executes automatically with defaults

### Structure

```yaml
scripts:
  <script_name>:
    <action_name>:                 # Action key (e.g., "config", "install")
      autoscript: true             # Optional: enable automation for this action
      answers:                     # Prompt answers (array)
        - default: "value1"        # Answer to prompt 1
        - default: "value2"        # Answer to prompt 2
```

**OR for interactive-only (no automation):**

```yaml
scripts:
  <script_name>:
    <action_name>:
      - default: "value1"          # Interactive answers (direct array)
      - default: "value2"
```

### Examples

#### Example 1: Interactive (User Sees Prompts)

```yaml
scripts:
  git:
    config:
      - default: "myuser"           # Username default
      - default: "me@example.com"   # Email default
```

**Usage:**
```
Git username? [myuser]: 
  (Press ENTER for default, or type new value)
Git email? [me@example.com]: 
  (Press ENTER for default, or type new value)
```

#### Example 2: Autoscript on One Action (No Prompts)

```yaml
scripts:
  ubuntu:
    install:
      - default: "no"               # Interactive
    pro:
      autoscript: true              # Automated (this action only!)
      answers:
        - default: "token123"
```

**Usage:**
```
ubuntu → install → shows prompts (interactive)
ubuntu → pro → no prompts (automated)
```

#### Example 3: Multiple Actions, Mixed Modes

```yaml
scripts:
  docker:
    install:
      - default: "yes"              # Interactive
    config:
      autoscript: true              # Automated
      answers:
        - default: "dockeruser"
  
  postgres:
    config:
      - default: "mydb"
      - default: ""                 # User must type (no default)
```

### Important Notes

- **Script/action names:** Must match the catalog exactly (case-sensitive)
- **Action name:** Use the `parameter` value from the catalog actions
- **Quote values:** Always use `"quotes"` around defaults
- **Empty default:** Use `default: ""` if user must type (no suggestion)
- **Fallback:** If answer.yaml missing/invalid → uses the catalog defaults
- **Graceful fallback:** If autoscript present but answers missing → shows prompts anyway
- **Per-action:** Each action can have independent automation

### When to Use Each Mode

**Interactive (default):**
- Development and testing
- Manual configuration
- User wants to override defaults
- Good for: ad-hoc tasks

**Autoscript (autoscript: true on action):**
- CI/CD pipelines
- Batch operations
- Repeated deployments
- Server provisioning
- Good for: automation and reproducibility

### Best Practices

1. **Use interactive for manual tasks** (omit autoscript field)
   ```yaml
   git:
     config:
       - default: "corp-user"       # User can override
   ```

2. **Use autoscript for repetitive actions** (add autoscript: true)
   ```yaml
   linux:
     install:
       autoscript: true             # Automate just the install
       answers:
         - default: "yes"
   ```

3. **Provide empty defaults for sensitive data**
   ```yaml
   postgres:
     config:
       - default: "mydb"            # Database name (safe)
       - default: ""                # Password (user must type!)
   ```

4. **Test before enabling autoscript**
   - First run as interactive (without autoscript) to verify defaults work
   - Then add `autoscript: true` once confident
   - Keep interactive for development/testing

### Automation Logic

1. **Check:** Is `autoscript: true` set for this action?
2. **If yes:** Are all required answers present in `.answers[]`?
   - **All present:** Skip prompts, run automatically
   - **Any missing:** Show interactive prompts (graceful fallback)
3. **If no:** Always show interactive prompts

### Works With Custom Repos

Custom repositories use the **same answer.yaml** as main ulh:

```yaml
scripts:
  hello:                  # Custom repo script
    run:
      autoscript: true
      answers:
        - default: "World"
```

**Automatic:** Load answers → detect OS → execute script. Same as system scripts.

### Troubleshooting answer.yaml

**Defaults not loading?**
- Check: `.scripts.${script}.${action}` path exists
- Check: Script/action names match the catalog (case-sensitive)
- Check: YAML valid: `apps/cli/vendor/yq/yq-amd64 eval 'keys' apps/cli/config/answer.yaml`

**Autoscript not triggering?**
- Check: `autoscript: true` (not just `autoscript:`)
- Check: All answers present for all prompts
- Check: Action name matches the catalog parameter value

**Falls back to interactive?**
- Expected: If answers are incomplete
- Intentional: Graceful degradation instead of failure
- Solution: Add missing answers to `answers:` array

---

## Custom Repositories

Your own scripts live in repositories of their own - a folder, or a git
repository ulh clones for you. Each one is `apps/cli/data/repos/<path>/` with a
`config.yaml` (same layout as the catalog, scripts referenced by `path`) and a
`scripts/` folder. The demo in `apps/cli/data/repos/demo-scripts/` shows it all;
switch it on in `apps/cli/config/repo.yaml`.

### Setup

1. **Create repository structure:**

```bash
mkdir my-scripts
cd my-scripts

cat > config.yaml << 'EOF'
scripts:
  backup:
    description: "Backup utility"
    path: "backup.sh"
    
    actions:
      - name: "run"
        parameter: "run"
        description: "Execute backup"
        prompts:
          - question: "Backup directory?"
            variable: "BACKUP_DIR"
            type: "text"
            default: "/backups"
EOF

mkdir -p scripts
cat > scripts/backup.sh << 'EOF'
#!/bin/bash
# Your backup script here
ACTION="${1%%,*}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
echo "Backing up to: $BACKUP_DIR"
EOF

git init
git add .
git commit -m "Initial commit"
```

2. **Edit ulh's apps/cli/config/repo.yaml:**

```yaml
repositories:
  my-scripts:
    name: "My Scripts"
    url: "https://github.com/user/my-scripts.git"
    path: "my-scripts"
    auth_method: "none"
    enabled:              # Show in menu
    auto_update:          # Auto-pull on startup (optional)
```

3. **ulh handles the rest** - Auto-clone into `apps/cli/data/repos/my-scripts/`, sync, execute

Without git: leave `url: ""` and put the folder into `apps/cli/data/repos/` yourself.

**Note:** Custom repos use `config.yaml` (not custom.yaml), same layout as ulh's catalog.

### ulh's helpers in your scripts

A script in `data/repos/<repo>/scripts/` can load ulh's helpers
(`parse_parameters`, `log_info`, `msg_ok`, `detect_os`, the `PKG_*` variables):

```bash
source "$(dirname "$0")/../../../lib/bootstrap.sh"
parse_parameters "$1"
```

That path is the same as in old installations (`custom/<repo>/scripts/`): ulh
generates `apps/cli/data/lib/` with small forwarders to `classes/`, so existing
scripts keep working unchanged.

### Authentication Methods

**SSH (Recommended)**
```yaml
repositories:
  private:
    url: "git@github.com:org/scripts.git"
    auth_method: "ssh"
    ssh_key: "id_rsa"
```

SSH key resolution:
1. `apps/cli/data/keys/id_rsa` ← Recommended (git-ignored)
2. `~/.ssh/id_rsa` ← Fallback

**HTTPS Token**
```yaml
repositories:
  github:
    url: "https://github.com/org/scripts.git"
    auth_method: "https_token"
    token: "${GITHUB_TOKEN}"  # From environment
```

**HTTPS Basic Auth**
```yaml
repositories:
  company:
    url: "https://git.company.com/scripts.git"
    auth_method: "https_basic"
    username: "${GIT_USER}"
    password: "${GIT_PASS}"
```

**Public (No Auth)**
```yaml
repositories:
  community:
    url: "https://github.com/public/scripts.git"
    auth_method: "none"
```

### Flag Combinations

| enabled: | auto_update: | Behavior |
|----------|--------------|----------|
| ✓ (present) | ✓ (present) | Show in menu + auto-pull on startup |
| ✓ (present) | (absent) | Show in menu, no auto-pull |
| (absent) | ✓ (present) | Hidden from menu, but auto-pull on startup |
| (absent) | (absent) | Completely ignored |

---

## Script Development

### Using the Template

```bash
cp apps/cli/templates/script-template.sh apps/cli/assets/scripts/my-script.sh
```

**script-template.sh** provides:
- Parameter parsing (`action,VAR1=val1,VAR2=val2`)
- Modern logging functions
- `detect_os()` for all 5 distributions
- Package manager variables (PKG_UPDATE, PKG_INSTALL, PKG_UNINSTALL)
- Standard action structure (install, update, uninstall, config)

### Complete Example

Every script in `apps/cli/assets/scripts/` follows this shape. `bootstrap.sh`
supplies `parse_parameters`, the `log_*` and `msg_*` helpers, `detect_os` with the
`PKG_*` variables, `command_exists` and `print_usage` - never reimplement those
locally.

```bash
#!/bin/bash

# my-script.sh - Custom web server
# Install, update, uninstall and configure it on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
parse_parameters "$1"

install_web_server() {
    log_info "Installing web server..."
    detect_os

    $PKG_UPDATE || true
    $PKG_INSTALL nginx || log_error "Failed to install"

    systemctl enable nginx
    systemctl start nginx

    log_info "Web server installed!"
}

update_web_server() {
    log_info "Updating web server..."
    detect_os

    $PKG_UPDATE || true
    $PKG_INSTALL nginx || log_error "Failed to update"
    systemctl restart nginx

    log_info "Web server updated!"
}

uninstall_web_server() {
    log_warn "Uninstalling web server..."
    detect_os

    systemctl stop nginx || true
    systemctl disable nginx || true
    $PKG_UNINSTALL nginx || log_error "Failed to uninstall"

    log_info "Web server uninstalled!"
}

configure_web_server() {
    log_info "Configuring web server..."

    # variables come from the prompts defined in the catalog
    PORT="${PORT:-80}"
    log_info "Port: $PORT"

    systemctl restart nginx
    log_info "Configuration updated!"
}

case "$ACTION" in
    install)   install_web_server ;;
    update)    update_web_server ;;
    uninstall) uninstall_web_server ;;
    config)    configure_web_server ;;
    *)         print_usage my-script && exit 1 ;;
esac
```

**Note on `sudo`:** scripts with `sudo:` in the catalog already run as root, so
call `systemctl` and the package manager directly - no `sudo` prefix inside the
script.

**Note on nested `case` blocks:** if a function contains its own `case` (an
interactive submenu, an architecture switch), it has a `*)` branch of its own.
When editing the action dispatcher at the bottom of a file, make sure you are
looking at the last `case "$ACTION"` block - a search-and-replace that grabs the
first `*)` in the file will silently eat everything between the two. That is
exactly how `ufw.sh` and `docker-compose.sh` lost half their code in 0668654.

### Guidelines

1. **Source bootstrap.sh** - Never reimplement logging, parsing or OS detection
2. **Use `detect_os()`** - Always detect, don't hardcode package managers
3. **Support all 5 families** - Debian, Red Hat, Arch, SUSE, Alpine
4. **Proper error handling** - Use `log_error` to exit cleanly
5. **Service management** - Enable and start services where applicable
6. **Unknown action** - End the dispatcher with `print_usage <name> && exit 1`
7. **Keep the catalog in sync** - Every action in the script needs an entry in
   `apps/cli/assets/catalog.yaml`, and every entry needs a matching branch in the `case`
8. **Clean formatting** - Indent properly, use descriptive variable names
9. **Test** - Run `bash apps/cli/tests/run.sh` before committing (Linux)

`tests/run.sh` checks the syntax of every script, that catalog and script files
match, that every script answers an unknown action with its usage, and runs the
menu, the move of old `custom/` folders and the demo repository - without
installing anything. Quick syntax check on its own:

```bash
for f in apps/cli/assets/scripts/*.sh; do bash -n "$f" || echo "BROKEN: $f"; done
```

---

## Menu System

### Header & Footer

All menus use consistent 80-character box formatting:

```
+==============================================================================+
| ulh - unknown linux helper                         VERSION: 0.5 |
+==============================================================================+
|
   [menu items here]
|
+==============================================================================+
|   q) Quit                                   ubuntu (debian) · v25.10 |
+==============================================================================+
```

### Navigation

**Repository Selector** (Root)
- Shows: ulh Scripts + all enabled Custom Repos
- Actions: Select repo → enter its menu

**ulh Scripts Menu**
- Shows: Categories (Essential Tools, Databases, etc.)
- Context-aware: Back button only if coming from repo selector
- Actions: Select category → show scripts, or `s` / `/term` → search

**Search** (repository selector, category list and script list)
- Trigger: `s` for a prompt, or type `/term` directly at any `Choose:` prompt
- Matches: script name + description + category, case-insensitive substring
- Filtered: only scripts compatible with the running distro and present on disk
- Result: pick a number → jumps straight into that script's action menu
- Inside the results: `s` starts a new search, `b` returns to the previous menu
- Implementation: `get_search_results()` zips the three yq lists
  (`yaml_scripts`, `yaml_all_descriptions`, `yaml_all_categories`) and filters in
  bash - no per-script yq calls, the OS check runs only for hits
- Scope: system scripts from the catalog (custom repo scripts are not indexed)

**Script Menu**
- Shows: Scripts in selected category with descriptions
- Actions: Select script → show actions

**Action Menu**
- Shows: Available actions for selected script
- Actions: Select action → execute with prompts

---

## Troubleshooting

### `/bin/bash^M: bad interpreter`

**Cause:**
The files carry CRLF line endings. This happens when ulh is copied to the target
machine from a Windows working copy (SMB, SCP, rsync) instead of being cloned.
`.gitattributes` pins everything to LF, so a `git clone` is never affected.

**Solution:**
```bash
find ~/ulh -type f \( -name '*.sh' -o -name '*.yaml' -o -name '*.md' \) \
    -exec sed -i 's/\r$//' {} +
```
Leaves `apps/cli/vendor/yq/` alone - those are binaries and must not be touched.
Better: re-clone, which also restores the `.git` directory the auto-update needs.

### Scripts fail to run

**Check:**
- Syntax: `bash -n apps/cli/assets/scripts/my-script.sh`
- Dependencies: `which git` (git required)

ulh runs every script with `bash`, so scripts don't need the executable bit.

### Custom repo not cloning

**Check:**
- URL is valid: `git clone [URL] /tmp/test`
- SSH key exists: `ls -la apps/cli/data/keys/id_rsa`
- SSH key permissions: `chmod 600 apps/cli/data/keys/id_rsa`

**Solution:**
- Test git access manually
- Check SSH key passphrase
- Verify GitHub/server SSH settings

### Package installation fails

**Check:**
- OS detection: `source /etc/os-release && echo $ID`
- Package name valid for distro
- Network: `ping github.com`

**Solution:**
- Try manual installation: `sudo apt-get install package`
- Check package manager status: `sudo apt-get update`

### Menu looks broken

**Check:**
- Terminal width: `tput cols` (should be ≥80)
- TERM variable: `echo $TERM`
- Locale: `locale` (should include UTF-8)

**Solution:**
- Resize terminal or use screen multiplexer
- Set TERM: `export TERM=xterm-256color`

### Update stops with an error

ulh updates itself with `git pull` and only fast-forward. If you changed files
that ulh ships (for example the catalog), the pull stops and ulh keeps running
the old version. Check with `git -C ~/ulh status`; your own files belong into
`apps/cli/config/` and `apps/cli/data/`, which updates never touch.

---

## API Reference

### Core Functions (classes/core.sh)

```bash
# Logging
msg_info "message"      # Cyan ℹ
msg_ok "message"        # Green ✓
msg_warn "message"      # Yellow ⚠
msg_err "message"       # Red ✗ (does not exit)
die "message"           # Red ✗ + exit 1

# OS Detection
detect_os()            # Sets OS_DISTRO, OS_FAMILY, OS_VERSION
```

### Menu Functions (classes/menu.sh)

```bash
menu_header "Title"                # Unified 80-char header
menu_footer 0|1 [0|1]              # Footer (back button, search hint)
menu_clear                         # Clear terminal
menu_search "term"                 # Result list -> jumps into menu_actions
menu_ask_search                    # Prompts for a term, then menu_search
get_search_results results "term"  # Fills array with "name|description|category"
```

### Repository Functions (classes/repos.sh)

```bash
repo_init               # Initialize all custom repos on startup
repo_sync_all           # Clone/pull all enabled repos
repo_list_enabled       # Get list of enabled repo names
repo_get_name           # Get display name for repo
```

### Execution (classes/execute.sh)

```bash
execute_action          # Run script with parameters
execute_custom_repo_action  # Run custom repo script
```

**`load_answers()`**
- Loads answer.yaml once per session (cached)
- Derives path from `ulh_DIR` or BASH_SOURCE fallback
- Validates YAML syntax with yq
- Returns 0 if loaded, 1 if missing/invalid

**`get_action_autoscript(script_name, action_name)`**
- Checks if `.scripts.${script}.${action}.autoscript` == true
- Returns 0 if true, 1 if false/missing
- Used to enable/disable automation for specific action

**`get_answer_default(script_name, action_name, prompt_index)`**
- Retrieves `.scripts.${script}.${action}.answers[index].default`
- Fallback: tries old format `.scripts.${script}.${action}[index].default`
- Returns empty string if not found
- Used by both interactive and autoscript modes

**`has_all_answers(script_name, action_name, prompt_count)`**
- Verifies all `prompt_count` answers exist
- Returns 0 if complete, 1 if any missing
- Enables fallback to interactive when autoscript incomplete

**`prompt_by_type(question, type, default, autoscript_mode)`**
- If autoscript + default present: return default directly
- Else: show interactive prompt with `[default]` shown
- Validates: yes/no, number, text, required/optional
- Returns user input or default

### Update and your files (classes/update.sh, classes/userdata.sh)

```bash
update_auto             # On start: pull if behind, then restart ulh
update_check            # --check-update
update_apply            # --update
userdata_migrate        # Move an old custom/ folder to config/ and data/
userdata_init           # Create repo.yaml, the demo repo and data/lib/ if missing
```

### Library Map

| File | Responsibility | Key functions |
|------|----------------|---------------|
| `classes/bootstrap.sh` | sourced by every script in `assets/scripts/` | `parse_parameters`, `log_*`, `msg_*`, `detect_os`, `command_exists`, `print_usage` |
| `classes/colors.sh` | ANSI color codes | `$RED`, `$GREEN`, `$C_CYAN`, `separator`, `separator_dots` |
| `classes/core.sh` | menu-side OS detection and messages | `detect_os`, `msg_info`, `msg_ok`, `msg_warn`, `msg_err` |
| `classes/yaml.sh` | reads the catalog through yq | `yaml_load`, `yaml_scripts`, `yaml_scripts_by_cat`, `yaml_all_descriptions`, `yaml_action_*`, `yaml_prompt_*` |
| `classes/menu.sh` | renders and navigates the menus | `menu_main`, `menu_category`, `menu_actions`, `menu_search`, `menu_header/footer` |
| `classes/execute.sh` | collects answers and runs the script | `execute_action`, `prompt_by_type`, `get_answer_default`, `has_all_answers` |
| `classes/repos.sh` | custom repositories | `repo_init`, `repo_sync_all`, `repo_list_enabled`, `repo_get_path` |
| `classes/update.sh` | self-update via git | `update_auto`, `update_check`, `update_apply` |
| `classes/userdata.sh` | your files in `config/` and `data/` | `userdata_migrate`, `userdata_init` |

---

## Support

- **GitHub Issues**: https://github.com/sorglos-it/ulh/issues
- **Documentation**: See [README](../README.md) + [scripts.md](scripts.md)
- **Script Examples**: Check `apps/cli/assets/scripts/`

---

**Last Updated:** 2026-09-22 | **Version:** 0.5

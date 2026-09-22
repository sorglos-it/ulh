# ulh Documentation

Complete guide to ulh v0.5 architecture, configuration, and development.

**96 scripts across 16 categories** | Multi-distro support | Per-action automation

## Table of Contents

1. [Architecture](#architecture)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [Answer File (answer.yaml)](#answer-file-answeryaml)
5. [Custom Repositories](#custom-repositories)
6. [Script Development](#script-development)
7. [Menu System](#menu-system)
8. [Troubleshooting](#troubleshooting)

---

## Architecture

### Design Philosophy

ulh prioritizes simplicity, consistency, and maintainability:

- **Single Entry Point** - `ulh.sh` orchestrates everything
- **Focused Libraries** - Each file handles one responsibility
- **Explicit Parameters** - Comma-separated strings, no silent globals
- **Cross-Platform** - All scripts work on 5+ distribution families
- **Auto-Updating** - Transparent self-updates with `exec` restart

### File Structure

```
ulh/
├── ulh.sh              # Main entry (auto-update + repo init)
├── lib/                # 7 focused libraries
│   ├── bootstrap.sh    # Parameter parsing, OS detection, logging, print_usage()
│   ├── colors.sh       # Centralized ANSI color definitions
│   ├── core.sh         # OS convenience functions
│   ├── execute.sh      # Script execution engine with autoscript support
│   ├── menu.sh         # Menu display + navigation
│   ├── repos.sh        # Repository sync + management
│   └── yaml.sh         # YAML parsing via yq binary
├── scripts/            # 96 scripts, one file per program
│   └── Multiple categories:
│       ├── Essential Tools (10)
│       ├── Text Editors (6)
│       ├── Shells & Terminals (5)
│       ├── Web Servers (2)
│       ├── Databases (3)
│       ├── Container & Virtualization (8)
│       ├── Programming Languages (10)
│       ├── Development Tools (4)
│       ├── System Utilities (15)
│       ├── Backup & Sync (2)
│       ├── Monitoring & Logging (4)
│       ├── Networking (11)
│       ├── System Management (7)
│       ├── Package Managers (4)
│       ├── Security & Sandboxing (4)
│       └── Multimedia (1)
├── custom/             # User repositories (git-ignored except repo.yaml)
│   ├── repo.yaml       # Repository configuration
│   ├── answer.yaml     # Script defaults + automation config
│   ├── keys/           # SSH keys (.gitignore protected)
│   └── [custom-repos]/ # Cloned repositories
├── config.yaml         # System scripts configuration (96 scripts)
├── README.md           # Quick start guide
├── SCRIPTS.md          # Script reference table (all 96 scripts)
├── TREE.md             # File map: path, actions, sudo and distros per script
└── DOCS.md             # This file
```

**Looking for a specific script?** [TREE.md](TREE.md) lists every script with its
file path, available actions, sudo requirement and supported distributions, plus a
grep cheat sheet for finding things from the shell.

### Execution Flow

1. `ulh.sh` starts → sets UTF-8 locale, enables bash strict mode
2. Auto-update check → git fetch + pull (if updates exist, `exec` restart)
3. Load libraries → core, yaml, menu, execute, repos
4. Initialize repositories → clone/sync custom repos
5. Show menu → repository selector or ulh scripts directly
6. Execute action → call script with parameters
7. Return to menu

---

## Installation

### Automatic (One-liner wget)

```bash
wget -qO - https://raw.githubusercontent.com/sorglos-it/ulh/main/install.sh | bash
```

### Automatic (One-liner curl)
```bash
curl -sSL https://raw.githubusercontent.com/sorglos-it/ulh/main/install.sh | bash
```

Then:
```bash
cd ~/ulh && bash ulh.sh
```

### Manual Clone

```bash
git clone https://github.com/sorglos-it/ulh.git
cd ulh
bash ulh.sh
```

### Platform-Specific

**install.sh** automatically:
- Detects OS (Debian, Red Hat, Arch, SUSE, Alpine)
- Installs git (only dependency)
- Clones/updates ulh
- Works with or without sudo (detects if running as root)

---

## Configuration

### System Scripts (config.yaml)

Controls built-in ulh scripts at repo root:

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
    category: "Database"
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
- `file` - Script path (relative to scripts/)
- `sudo:` - Elevate with sudo (presence-based, optional)
- `os_family` - Supported distributions (optional)
- `os_only` - Single distro (optional, overrides os_family)
- `os_exclude` - Blacklist distros (optional)

**Prompt Types:**
- `text` - Free input
- `yes/no` - Boolean
- `number` - Numeric input

---

## Answer File (answer.yaml)

### What It Does

The `custom/answer.yaml` file provides **default values for prompts** and enables **per-action automation** via the `autoscript` flag.

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

- **Script/action names:** Must match config.yaml exactly (case-sensitive)
- **Action name:** Use the `parameter` value from config.yaml actions
- **Quote values:** Always use `"quotes"` around defaults
- **Empty default:** Use `default: ""` if user must type (no suggestion)
- **Fallback:** If answer.yaml missing/invalid → uses config.yaml defaults
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

---

## Custom Repositories

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
BACKUP_DIR="${BACKUP_DIR:-/backups}"
echo "Backing up to: $BACKUP_DIR"
EOF

chmod +x scripts/backup.sh
git init
git add .
git commit -m "Initial commit"
```

2. **Edit ulh's custom/repo.yaml:**

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

3. **ulh handles the rest** - Auto-clone, sync, execute

**Note:** Custom repos use `config.yaml` (not custom.yaml), same as main ulh structure.

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
1. `custom/keys/id_rsa` ← Recommended (protected by .gitignore)
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
cp scripts/_template.sh scripts/my-script.sh
```

**_template.sh** provides:
- Parameter parsing (`action,VAR1=val1,VAR2=val2`)
- Modern logging functions
- `detect_os()` for all 5 distributions
- Package manager variables (PKG_UPDATE, PKG_INSTALL, PKG_UNINSTALL)
- Standard action structure (install, update, uninstall, config)

### Complete Example

Every script in `scripts/` follows this shape. `bootstrap.sh` supplies
`parse_parameters`, the `log_*` helpers, `detect_os` with the `PKG_*` variables,
`command_exists` and `print_usage` - never reimplement those locally.

```bash
#!/bin/bash

# my-script.sh - Custom web server
# Install, update, uninstall and configure it on all Linux distributions

set -e
source "$(dirname "$0")/../lib/bootstrap.sh"
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

    # variables come from the prompts defined in config.yaml
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

**Note on `sudo`:** scripts with `sudo:` in config.yaml already run as root, so
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
7. **Keep config.yaml in sync** - Every action in the script needs an entry, and
   every entry needs a matching branch in the `case`
8. **Clean formatting** - Indent properly, use descriptive variable names
9. **Test syntax** - Run `bash -n script.sh` before committing

Quick check that every script still dispatches what config.yaml advertises:

```bash
for f in scripts/*.sh; do bash -n "$f" || echo "BROKEN: $f"; done
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
- Scope: system scripts from config.yaml (custom repo scripts are not indexed)

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
Leaves `lib/yq/` alone - those are binaries and must not be touched. Better:
re-clone, which also restores the `.git` directory the auto-update needs.

### Scripts fail to run

**Check:**
- Syntax: `bash -n scripts/my-script.sh`
- Permissions: `ls -la scripts/*.sh` (should be executable)
- Dependencies: `which git` (git required)

**Solution:**
ulh auto-chmods scripts, but verify manually if needed.

### Custom repo not cloning

**Check:**
- URL is valid: `git clone [URL] /tmp/test`
- SSH key exists: `ls -la custom/keys/id_rsa`
- SSH key permissions: `chmod 600 custom/keys/id_rsa`

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

---

## API Reference

### Core Functions (lib/core.sh)

```bash
# Logging
msg_info "message"      # Green ✓
msg_warn "message"      # Yellow ⚠
msg_err "message"       # Red ✗ + exit 1

# OS Detection
detect_os()            # Sets OS_DISTRO, PKG_* variables
```

### Menu Functions (lib/menu.sh)

```bash
menu_header "Title"                # Unified 80-char header
menu_footer 0|1 [0|1]              # Footer (back button, search hint)
menu_clear                         # Clear terminal
menu_search "term"                 # Result list -> jumps into menu_actions
menu_ask_search                    # Prompts for a term, then menu_search
get_search_results results "term"  # Fills array with "name|description|category"
```

### Repository Functions (lib/repos.sh)

```bash
repo_init               # Initialize all custom repos on startup
repo_sync_all           # Clone/pull all enabled repos
repo_list_enabled       # Get list of enabled repo names
repo_get_name           # Get display name for repo
```

### Execution (lib/execute.sh)

```bash
execute_action          # Run script with parameters
execute_custom_repo_action  # Run custom repo script
```

---

## Support

- **GitHub Issues**: https://github.com/sorglos-it/ulh/issues
- **Documentation**: See README.md + SCRIPTS.md + TREE.md
- **Script Examples**: Check scripts/ directory

---

## Answer.yaml + Autoscript Details

### Per-Action Autoscript (v0.5)

Autoscript is now **per-action**, not per-script. Each action can be independently automated:

```yaml
scripts:
  ubuntu:
    install:                     # Interactive action
      - default: "no"
    pro:                         # Automated action
      autoscript: true
      answers:
        - default: "token123"
```

**Key:** `autoscript: true` on the **action level**, not the script level.

### Automation Logic

1. **Check:** Is `autoscript: true` set for this action?
2. **If yes:** Are all required answers present in `.answers[]`?
   - **All present:** Skip prompts, run automatically
   - **Any missing:** Show interactive prompts (graceful fallback)
3. **If no:** Always show interactive prompts

### Function Reference

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

### Troubleshooting

**Defaults not loading?**
- Check: `.scripts.${script}.${action}` path exists
- Check: Script/action names match config.yaml (case-sensitive)
- Check: YAML valid: `yq eval 'keys' custom/answer.yaml`

**Autoscript not triggering?**
- Check: `autoscript: true` (not just `autoscript:`)
- Check: All answers present for all prompts
- Check: Action name matches config.yaml parameter value

**Falls back to interactive?**
- Expected: If answers are incomplete
- Intentional: Graceful degradation instead of failure
- Solution: Add missing answers to `answers:` array

---

**Last Updated:** 2026-08-11 | **Version:** 0.5

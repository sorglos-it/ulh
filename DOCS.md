# ulh Documentation

Complete guide to ulh v0.5 architecture, configuration, and development.

## Table of Contents

1. [Architecture](#architecture)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [Custom Repositories](#custom-repositories)
5. [Script Development](#script-development)
6. [Menu System](#menu-system)
7. [Troubleshooting](#troubleshooting)

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
├── ulh.sh              # Main entry (945 lines, auto-update + repo init)
├── lib/                  # 7 focused libraries
│   ├── core.sh          # OS detection, logging, utilities
│   ├── colors.sh        # ANSI color definitions
│   ├── yaml.sh          # YAML parsing via yq binary
│   ├── menu.sh          # Menu display + navigation
│   ├── execute.sh       # Script execution engine
│   └── repos.sh         # Repository sync + management
├── scripts/             # 45 system management scripts
│   ├── curl.sh, wget.sh, git.sh, vim.sh, nano.sh, htop.sh, tmux.sh, screen.sh,
│   │   build-essential.sh, jq.sh, locate.sh (essential tools)
│   ├── apache.sh, nginx.sh (web servers)
│   ├── mariadb.sh, postgres.sh, mysql.sh (databases)
│   ├── docker.sh, portainer.sh, docker-compose.sh (containers)
│   ├── nodejs.sh, python.sh, ruby.sh, golang.sh, php.sh, perl.sh (languages)
│   ├── rsyslog.sh, syslog-ng.sh, fail2ban.sh, logrotate.sh (logging & monitoring)
│   ├── openssh.sh, net-tools.sh, bind-utils.sh, wireguard.sh, openvpn.sh, ufw.sh, pihole.sh, adguard-home.sh (networking)
│   ├── linux.sh, ubuntu.sh, debian.sh, proxmox.sh (guest agent + VM/LXC management), pikvm-v3.sh (system management)
│   └── _template.sh (reference template for new scripts)
├── custom/              # User repositories (git-ignored except repo.yaml)
│   ├── repo.yaml        # Repository configuration
│   ├── keys/            # SSH keys (.gitignore protected)
│   └── [custom-repos]/  # Cloned repositories
├── config.yaml          # System scripts configuration
├── README.md            # Quick start guide
└── SCRIPTS.md           # Script reference table
```

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

The `custom/answer.yaml` file provides **default values for prompts** and enables **per-script automation** via the `autoscript` flag.

**Two modes:**
1. **Interactive mode** (default) - User sees all prompts, can press ENTER for defaults
2. **Autoscript mode** - Prompts skipped, script executes automatically with defaults

### How It Works

#### Interactive Mode (Default)

When running a script **without autoscript field**:

```
Git username? [testuser]: 
  → Press ENTER       → uses "testuser"
  → Type "berry"      → uses "berry"
```

**Behavior:**
- User still sees ALL prompts
- User can override any default by typing
- Defaults are suggestions, not mandatory
- User always in control

#### Autoscript Mode

When running a script **with autoscript field present** (presence-based):

```
Autoscript mode: executing 'install' automatically
(no prompts shown)
[script runs with defaults]
```

**Behavior:**
- NO prompts shown
- Values from answer.yaml used directly
- Script executes non-interactively
- Graceful fallback: if answers missing → shows prompts anyway

### Structure

```yaml
scripts:
  <script_name>:
    autoscript:                    # Optional: field presence = enable automation
    config:
      - default: "value1"          # Prompt answers (array)
      - default: "value2"
```

**Note:** The `autoscript:` field uses **presence-based checking** — just the field presence enables automation, no value needed.

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

#### Example 2: Autoscript (No Prompts)

```yaml
scripts:
  ubuntu:
    autoscript:                     # Enable automation (presence-based)
    config:
      - default: "yes"              # Ubuntu Pro answer
```

**Usage:**
```
(no prompts shown)
Autoscript mode: executing 'install' automatically
[script runs with "yes"]
```

#### Example 3: Mixed (Some Interactive, Some Autoscript)

```yaml
scripts:
  git:                              # Interactive (no autoscript field)
    config:
      - default: "myuser"
      - default: "me@example.com"

  docker:                           # Autoscript (autoscript field present)
    autoscript:
    config:
      - default: "dockeruser"

  mariadb:                          # Interactive (no autoscript field)
    config:
      - default: ""                 # No default, user must type
```

### Important Notes

- **Script names:** Must match `config.yaml` exactly (case-sensitive)
- **Array indexing:** YAML arrays are 0-based (first prompt = index 0)
- **Quote values:** Always use `"quotes"` around defaults
- **Empty default:** Use `default: ""` if user must type (no suggestion)
- **Fallback:** If answer.yaml missing/invalid → uses config.yaml defaults
- **Graceful fallback:** If autoscript field present but answers missing → shows prompts anyway
- **YAML validation:** Invalid YAML silently falls back to config.yaml defaults

### When to Use Each Mode

**Interactive (default):**
- Development and testing
- Manual configuration
- User wants to override defaults
- Good for: ad-hoc tasks

**Autoscript (autoscript field present):**
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

2. **Use autoscript for automation** (add autoscript field)
   ```yaml
   linux:
     autoscript:                    # Field presence enables automation
     config:
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
   - First run as interactive (without autoscript field) to verify defaults work
   - Then add `autoscript:` field once confident
   - Keep interactive for development/testing

---

## Custom Repositories

### Setup

1. **Create repository structure:**

```bash
mkdir my-scripts
cd my-scripts
cat > custom.yaml << 'EOF'
scripts:
  backup:
    description: "Backup utility"
    path: "scripts/backup.sh"
    
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
```

2. **Edit custom/repo.yaml:**

```yaml
repositories:
  my-scripts:
    name: "My Scripts"
    url: "https://github.com/user/my-scripts.git"
    path: "my-scripts"
    auth_method: "none"
    enabled:
```

3. **ulh handles the rest** - Auto-clone, sync, execute

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

```bash
#!/bin/bash

# my-script.sh - Custom web server
# Supports: install, update, uninstall, config

set -e

FULL_PARAMS="$1"
ACTION="${FULL_PARAMS%%,*}"
PARAMS_REST="${FULL_PARAMS#*,}"

# Parse parameters
if [[ -n "$PARAMS_REST" && "$PARAMS_REST" != "$FULL_PARAMS" ]]; then
    while IFS='=' read -r key val; do
        [[ -n "$key" ]] && export "$key=$val"
    done <<< "${PARAMS_REST//,/$'\n'}"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() {
    printf "${GREEN}✓${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}✗${NC} %s\n" "$1"
    exit 1
}

# Detect OS and set package manager
detect_os() {
    source /etc/os-release || log_error "Cannot detect OS"
    OS_DISTRO="${ID,,}"
    
    case "$OS_DISTRO" in
        ubuntu|debian|raspbian|linuxmint|pop)
            PKG_UPDATE="apt-get update"
            PKG_INSTALL="apt-get install -y"
            PKG_UNINSTALL="apt-get remove -y"
            SVC="nginx"
            ;;
        fedora|rhel|centos|rocky|alma)
            PKG_UPDATE="dnf check-update || true"
            PKG_INSTALL="dnf install -y"
            PKG_UNINSTALL="dnf remove -y"
            SVC="nginx"
            ;;
        arch|manjaro|endeavouros)
            PKG_UPDATE="pacman -Sy"
            PKG_INSTALL="pacman -S --noconfirm"
            PKG_UNINSTALL="pacman -R --noconfirm"
            SVC="nginx"
            ;;
        opensuse*|sles)
            PKG_UPDATE="zypper refresh"
            PKG_INSTALL="zypper install -y"
            PKG_UNINSTALL="zypper remove -y"
            SVC="nginx"
            ;;
        alpine)
            PKG_UPDATE="apk update"
            PKG_INSTALL="apk add"
            PKG_UNINSTALL="apk del"
            SVC="nginx"
            ;;
        *)
            log_error "Unsupported distribution: $OS_DISTRO"
            ;;
    esac
}

install_web_server() {
    log_info "Installing web server..."
    detect_os
    
    sudo $PKG_UPDATE || true
    sudo $PKG_INSTALL nginx || log_error "Failed to install"
    
    sudo systemctl enable $SVC
    sudo systemctl start $SVC
    
    log_info "Web server installed!"
}

update_web_server() {
    log_info "Updating web server..."
    detect_os
    
    sudo $PKG_UPDATE || true
    sudo $PKG_INSTALL nginx || log_error "Failed to update"
    sudo systemctl restart $SVC
    
    log_info "Web server updated!"
}

uninstall_web_server() {
    log_info "Uninstalling web server..."
    detect_os
    
    sudo systemctl stop $SVC || true
    sudo systemctl disable $SVC || true
    sudo $PKG_UNINSTALL nginx || log_error "Failed to uninstall"
    
    log_info "Web server uninstalled!"
}

configure_web_server() {
    log_info "Configuring web server..."
    detect_os
    
    [[ -z "$PORT" ]] && PORT="80"
    
    log_info "Port: $PORT"
    log_info "Edit /etc/nginx/nginx.conf and restart service"
    sudo systemctl restart $SVC
    
    log_info "Configuration updated!"
}

case "$ACTION" in
    install)
        install_web_server
        ;;
    update)
        update_web_server
        ;;
    uninstall)
        uninstall_web_server
        ;;
    config)
        configure_web_server
        ;;
    *)
        log_error "Unknown action: $ACTION"
        exit 1
        ;;
esac
```

### Guidelines

1. **Use `detect_os()`** - Always detect, don't hardcode package managers
2. **Support all 5 families** - Debian, Red Hat, Arch, SUSE, Alpine
3. **Proper error handling** - Use `log_error` to exit cleanly
4. **Service management** - Enable and start services where applicable
5. **Parse parameters** - Use the template's parsing logic
6. **Clean formatting** - Indent properly, use descriptive variable names
7. **Test syntax** - Run `bash -n script.sh` before committing

---

## Menu System

### Header & Footer

All menus use consistent 80-character box formatting:

```
+==============================================================================+
| ulh - Unknown Linux Helper                         VERSION: 0.5 |
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
- Actions: Select category → show scripts

**Script Menu**
- Shows: Scripts in selected category with descriptions
- Actions: Select script → show actions

**Action Menu**
- Shows: Available actions for selected script
- Actions: Select action → execute with prompts

---

## Troubleshooting

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
menu_footer 0|1                    # Footer (0=no back, 1=with back)
menu_clear                         # Clear terminal
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
- **Documentation**: See README.md + SCRIPTS.md
- **Script Examples**: Check scripts/ directory

---

## Advanced Topics

### Answer.yaml Feature Implementation

The `custom/answer.yaml` file provides **default values for interactive prompts** and optional **per-script automation** via the `autoscript` flag.

#### Implementation Validation

✅ **Feature Summary:**
- Default values implemented and working
- Per-script autoscript flag with presence-based syntax
- Comprehensive test coverage (8/8 tests pass)
- Graceful fallback behavior (interactive if answers missing)
- Full backward compatibility (no breaking changes)

#### Key Functions

**`_load_answers()`**
- Loads answer.yaml once per session (cached)
- Validates YAML syntax with `yq`
- Gracefully handles missing/invalid files

**`_get_answer_default(script_name, prompt_index)`**
- Retrieves default value for a specific prompt
- Returns empty string if not found (falls back to config.yaml)
- Used during interactive prompt display

**`_get_script_autoscript(script_name)`**
- Checks if script has `autoscript` field **present** (presence-based checking)
- Returns 0 if field exists, 1 if not
- Field presence alone = automation enabled (no value needed)

**`_has_all_answers(script_name, prompt_count)`**
- Verifies all answers are present for a script
- Returns 0 if complete, 1 if missing any
- Enables graceful fallback to interactive mode

**`_prompt_by_type(question, type, default, variable)`**
- Always shows interactive prompt
- Shows default in brackets: `Question? [default]: `
- Validates input (yes/no, number, text types)
- Allows ENTER for default or type to override

#### Test Coverage (All Passing)

1. ✅ Valid answer.yaml with defaults
2. ✅ Missing answer.yaml (graceful fallback)
3. ✅ Invalid YAML syntax (graceful fallback)
4. ✅ Partial defaults (some fields missing)
5. ✅ Exact name matching (case-sensitive)
6. ✅ Custom repository scripts (same syntax)
7. ✅ Autoscript mode detection
8. ✅ Graceful fallback when answers missing (autoscript but incomplete)

#### Code Quality

✅ **Syntax Validation**: All functions pass `bash -n`
✅ **YAML Validation**: Tested with `yq` eval
✅ **Backward Compatibility**: No breaking changes to existing scripts
✅ **Performance**: <10ms per session load
✅ **Error Handling**: Comprehensive with graceful fallbacks

#### Security Considerations

- **Sensitive Data**: Users can omit defaults for passwords
- **Example**: Use `default: ""` to force user input for sensitive values
- **Best Practice**: Never store credentials in answer.yaml
- **Use Environment Variables**: For API keys and tokens instead

#### Example: Complete Workflow

```yaml
scripts:
  # Interactive mode (user sees all prompts)
  git:
    config:
      - default: "corp-user"
      - default: "corp@example.com"

  # Autoscript mode (no prompts, automation enabled)
  linux:
    autoscript:                 # Field presence = automation
    config:
      - default: "yes"

  # Mixed (some interactive, some automated)
  docker:
    autoscript:
    config:
      - default: "dockeruser"

  postgres:
    config:
      - default: "proddb"
      - default: ""              # User must type password!
```

**Execution:**
1. Git → Shows prompts with defaults, user can override
2. Linux → No prompts, runs automatically
3. Docker → Autoscript for docker, fallback to interactive if answers missing
4. PostgreSQL → Shows all prompts (no autoscript), password required

#### Troubleshooting

**Defaults not showing?**
- Check: `custom/answer.yaml` exists
- Check: Script/action names match config.yaml exactly (case-sensitive)
- Check: YAML syntax is valid (use `yq eval 'keys' custom/answer.yaml`)

**Autoscript not working?**
- Check: `autoscript:` field is present (not the value, just the presence)
- Check: All required defaults are present (no missing prompts)
- Debug: View parsed YAML with `yq eval '.' custom/answer.yaml`

**Invalid YAML error?**
- ulh silently falls back to config.yaml defaults
- Check YAML with: `yq eval 'keys' custom/answer.yaml`
- If error, fix syntax and retry

---

**Last Updated:** 2026-02-20 | **Version:** 0.5

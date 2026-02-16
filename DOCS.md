# LIAUH - Complete Documentation

**Linux Install and Update Helper - Interactive menu system for managing system scripts**

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Directory Structure](#directory-structure)
3. [Quick Start](#quick-start)
4. [Configuration](#configuration)
5. [Creating Scripts](#creating-scripts)
6. [Architecture](#architecture)
7. [API Reference](#api-reference)
8. [Troubleshooting](#troubleshooting)

---

## Getting Started

LIAUH is a Bash-based system for organizing and executing scripts through an interactive menu interface. It handles:

- **Script organization** by category
- **Interactive prompts** before execution (text, yes/no, number)
- **OS compatibility filtering** (Debian, Red Hat, Arch, etc.)
- **Automatic sudo handling** with variable passthrough
- **Custom user scripts** in separate directory

### Features

✅ No chmod +x needed - LIAUH handles permissions automatically
✅ Variables from prompts passed securely to scripts
✅ OS detection and compatibility filtering
✅ Separate system and custom script management
✅ Full English documentation
✅ Debug mode for troubleshooting

---

## Directory Structure

```
liauh/
├── liauh.sh             # Main entry point (11 lines)
├── config.yaml          # System scripts configuration
├── custom.yaml          # Custom scripts configuration (optional)
├── README.md            # Quick reference
├── DOCS.md              # This file - complete documentation
│
├── lib/                 # Core libraries
│   ├── core.sh          # Colors, OS detection, utilities
│   ├── yaml.sh          # YAML configuration reader
│   ├── menu.sh          # Interactive menu system
│   ├── execute.sh       # Script execution with prompts
│   └── yq/              # yq binary (architecture-specific)
│       ├── yq-amd64     # x86_64 architecture
│       ├── yq-arm64     # ARM 64-bit
│       ├── yq-arm       # ARM 32-bit
│       └── yq-386       # x86 32-bit
│
├── scripts/             # System scripts directory
│   ├── test_script.sh   # Test/example script
│   ├── template.sh      # Template for new scripts
│   └── [your scripts]   # Add your scripts here
│
└── custom/              # Custom scripts directory (optional)
    └── [your scripts]   # User-defined scripts
```

---

## Quick Start

### Install and Run LIAUH

**With wget:**
```bash
wget -qO - https://raw.githubusercontent.com/sorglos-it/liauh/main/install.sh | bash && ./liauh/liauh.sh
```

**With curl:**
```bash
curl -sSL https://raw.githubusercontent.com/sorglos-it/liauh/main/install.sh | bash && ./liauh/liauh.sh
```

**Manual:**
```bash
git clone https://github.com/sorglos-it/liauh.git
cd liauh && bash liauh.sh
```

### CLI Options

```bash
# Interactive menu (default - auto-updates on startup)
bash liauh.sh

# Start without auto-update check
bash liauh.sh --no-update

# Enable debug output
bash liauh.sh --debug

# Check for updates (requires git repository)
bash liauh.sh --check-update

# Apply latest updates manually (requires git repository)
bash liauh.sh --update
```

### Auto-Update Behavior

By default, LIAUH automatically:
1. Checks for updates from GitHub on every startup
2. Applies updates silently if available
3. Continues normally if update fails or offline
4. **Preserves** your `custom/` scripts and `custom.yaml`

**Why automatic?**
- Stay secure with latest patches
- Get bug fixes automatically
- System scripts stay current
- No manual intervention needed

**To disable auto-update:**
```bash
bash liauh.sh --no-update
```

**How it works:**
- Fetches from remote: `git fetch origin`
- Pulls changes: `git pull origin main/master`
- Falls back gracefully if git unavailable or offline
- Updates are non-blocking - if they fail, LIAUH starts anyway

### Main menu

```
LIAUH - Linux Install and Update Helper

Detected: ubuntu (debian) - 25.10

  1) database
  2) language
  3) security
  4) webserver

   c) Custom scripts

──────────────────────────────────────────────────────────────────────
   q) Quit
──────────────────────────────────────────────────────────────────────

Choose: 
```

---

## Configuration

### Main Config: config.yaml

Defines all available scripts with categories, actions, and prompts.

```yaml
# scripts:
#   [script_name]:                    # Unique identifier
#     description: "..."              # One-line description
#     category: "..."                 # Group: database, webserver, security, language, etc.
#     file: "..."                     # Script filename in scripts/ directory
#     needs_sudo: true                # (optional) Only if script requires root access
#                                     # If omitted or false, script runs as normal user
#     
#     os_only: ubuntu                 # (optional) Limit to specific distro (ubuntu, debian, etc.)
#     os_family: [debian|redhat|arch|suse|alpine]    # (optional) Limit to OS family
#     os_exclude:                     # (optional) Exclude specific distros
#       - raspbian
#     
#     actions:                        # What the script can do
#       - name: "install"             # Action name (shown in menu)
#         parameter: "install"        # Parameter passed to script ($1)
#         description: "..."          # (optional) Action description
#         prompts:                    # (optional) Questions to ask user
#           - question: "Domain?"
#             variable: "DOMAIN"      # Environment variable name
#             type: "text"            # Input type: text, yes/no, number
#             default: "localhost"    # (optional) Default value
```

### Example 1: Ubuntu-Only Script (using os_only)

```yaml
scripts:
  ubuntu-update:
    description: "Update Ubuntu system (handles 25.04 → 25.10 upgrades)"
    category: "system"
    file: "ubuntu-update.sh"
    needs_sudo: true
    os_only: ubuntu
    
    actions:
      - name: "update"
        parameter: "update"
        prompts: []
```

**Note:** Use `os_only: ubuntu` for Ubuntu-specific scripts (don't show on Debian, Linux Mint, etc.)

### Example 2: Debian Family Script

```yaml
scripts:
  apache2:
    description: "Apache2 web server"
    category: "webserver"
    file: "apache2.sh"
    needs_sudo: true
    os_family: debian
    os_exclude:
      - raspbian
    
    actions:
      - name: "install"
        parameter: "install"
        description: "Install Apache2"
        prompts:
          - question: "Domain name?"
            variable: "DOMAIN"
            type: "text"
            default: "localhost"
          
          - question: "Enable SSL?"
            variable: "SSL_ENABLED"
            type: "yes/no"
            default: "no"
          
          - question: "Admin email?"
            variable: "ADMIN_EMAIL"
            type: "text"
            default: "admin@localhost"
      
      - name: "remove"
        parameter: "remove"
        description: "Uninstall Apache2"
        prompts:
          - question: "Keep config files?"
            variable: "KEEP_CONFIG"
            type: "yes/no"
            default: "yes"
```

### Custom Scripts: custom.yaml

Same format as config.yaml, but:
- Must specify `script_dir: custom`
- Scripts stored in `custom/` directory instead of `scripts/`
- Only shown if scripts exist and are compatible with OS
- **NOT tracked by git** - customize locally without affecting repository

```yaml
script_dir: custom

scripts:
  my_backup:
    description: "My backup script"
    category: "maintenance"
    file: "my_backup.sh"
    needs_sudo: true
    
    actions:
      - name: "backup"
        parameter: "backup"
        prompts:
          - question: "Backup destination?"
            variable: "BACKUP_DIR"
            type: "text"
            default: "/backups"
```

### .gitignore

LIAUH includes a `.gitignore` file that excludes:
- `custom/` directory - your personal scripts
- `custom.yaml` - your personal configuration
- `logs/` - temporary log files

This allows you to safely pull updates from GitHub without conflicts with your local customizations.

**Workflow:**
```bash
# You customize locally
cp scripts/template.sh custom/my_script.sh
cat > custom.yaml << EOF
script_dir: custom
scripts:
  my_script:
    ...
EOF

# Updates from GitHub don't affect your custom files
bash liauh.sh --update
# custom/ and custom.yaml are untouched
```

### Prompt Types

| Type | Values | Example |
|------|--------|---------|
| **text** | Any non-empty string | `example.com`, `my_name` |
| **yes/no** | y, yes, n, no (case-insensitive) | `y` → becomes `yes`, `n` → becomes `no` |
| **number** | Digits only | `8080`, `30` |

---

## Creating Scripts

### Step 1: Create script file

No chmod +x needed - LIAUH handles permissions automatically!

```bash
cp scripts/template.sh scripts/my_script.sh
```

### Step 2: Edit your script

```bash
#!/bin/bash
# My Script
ACTION="${1:-install}"

case "$ACTION" in
    install)
        echo "Domain: $DOMAIN"
        echo "Port: $PORT"
        # Your installation logic
        exit 0
        ;;
    remove)
        # Your removal logic
        exit 0
        ;;
    *)
        echo "Unknown action: $ACTION"
        exit 1
        ;;
esac
```

### Step 3: Register in config.yaml or custom.yaml

```yaml
my_script:
  description: "My Script"
  category: "custom"
  file: "my_script.sh"
  needs_sudo: false
  
  actions:
    - name: "install"
      parameter: "install"
      prompts:
        - question: "Domain?"
          variable: "DOMAIN"
          type: "text"
          default: "example.com"
        
        - question: "Port?"
          variable: "PORT"
          type: "number"
          default: "8080"
```

### Step 4: Run LIAUH

Your script appears in the menu under "custom" category.

### Template.sh Reference

Use `scripts/template.sh` as a starting point:

```bash
#!/bin/bash
# Script description

ACTION="${1:-install}"

# Log functions
log_info()    { echo "[INFO] $*"; }
log_error()   { echo "[ERROR] $*" >&2; }
log_success() { echo "[SUCCESS] $*"; }

# Main logic
main() {
    case "$ACTION" in
        install)  handle_install ;;
        remove)   handle_remove ;;
        update)   handle_update ;;
        config)   handle_config ;;
        *)        log_error "Unknown action: $ACTION"; exit 1 ;;
    esac
}

handle_install() {
    log_info "Starting installation..."
    # Your logic here
    log_success "Done"
}

handle_remove() {
    log_info "Starting removal..."
    # Your logic here
    log_success "Done"
}

handle_update() {
    log_info "Starting update..."
    # Your logic here
    log_success "Done"
}

handle_config() {
    log_info "Starting configuration..."
    # Your logic here
    log_success "Done"
}

main
exit $?
```

---

## Architecture

### Startup Flow

```
liauh.sh
  ├─ Set LIAUH_DIR
  ├─ Source libraries: core, yaml, menu, execute
  ├─ detect_os()           → from core.sh
  ├─ yaml_load("config")   → from yaml.sh
  └─ menu_main()           → from menu.sh
```

### Execution Flow

```
User selects action
  ├─ Count prompts from YAML
  ├─ For each prompt:
  │   ├─ Show question + default
  │   ├─ Read input
  │   └─ Validate based on type
  ├─ Ask confirmation: Execute '[action]' now? (y/N)
  ├─ Build parameter string: action,VAR1=val1,VAR2=val2,...
  │   Example: install,DOMAIN=example.com,SSL=yes,EMAIL=admin@test.com
  └─ Execute script:
      ├─ If needs_sudo: true  → sudo bash script.sh "param_string"
      │                         Password cached by sudo (system-level)
      │                         LIAUH never handles the password
      └─ If needs_sudo: false → bash script.sh "param_string"
```

### Permission Handling

No chmod +x needed anywhere!

```bash
# In execute.sh: Auto-fix script permissions
[[ ! -x "$script_path" ]] && chmod +x "$script_path" 2>/dev/null

# In yaml.sh: Auto-fix yq binary permissions
[[ -f "$YQ" && ! -x "$YQ" ]] && chmod +x "$YQ" 2>/dev/null
```

Scripts can be distributed with 644 (rw-r--r--) permissions - LIAUH will make them executable when needed.

### Sudo & Password Caching

When `needs_sudo: true` is set:

1. **User confirms execution** → "Execute '[action]' now? (y/N)"
2. **LIAUH builds parameter string** → Comma-separated format
3. **Script executes with sudo** → `sudo bash script.sh "param_string"`
4. **Sudo caches password** → At system level, for ~15 minutes
5. **LIAUH never handles password** → Only sudo kernel/system handles it

**Security Advantage:** The password stays at the OS/kernel level. LIAUH never touches it - only sudo and the operating system manage credentials.

```bash
# What LIAUH does:
# 1. Build parameter string
param_string="install,DOMAIN=example.com,SSL=yes,EMAIL=admin@test.com"

# 2. Execute with sudo
sudo bash script.sh "$param_string"

# Sudo prompts for password (first time, then caches for ~15 min)
# All subsequent sudo commands use cached credentials
```

### Variable Passing

LIAUH passes variables as a **comma-separated parameter string**:

```
install,DOMAIN=example.com,SSL=yes,EMAIL=admin@test.com
```

Your script must parse this string:

```bash
#!/bin/bash

# Parse the comma-separated parameter string
FULL_PARAMS="$1"

# Extract action (everything before first comma)
ACTION="${FULL_PARAMS%%,*}"

# Extract remaining parameters (everything after first comma)
PARAMS_REST="${FULL_PARAMS#*,}"

# Parse variable assignments and export them
if [[ -n "$PARAMS_REST" && "$PARAMS_REST" != "$FULL_PARAMS" ]]; then
    while IFS='=' read -r key val; do
        if [[ -n "$key" ]]; then
            export "$key=$val"
        fi
    done <<< "${PARAMS_REST//,/$'\n'}"
fi

# Now variables are available
echo "Domain: $DOMAIN"
echo "Email: $EMAIL"

if [[ "$SSL_ENABLED" == "yes" ]]; then
    sudo apt-get install -y ssl-cert  # Uses cached sudo password
fi
```

**The template.sh file includes this parsing code - just copy it!**

### OS Compatibility

LIAUH detects OS and filters scripts automatically:

```bash
# Detect OS
detect_os()
  → Sets OS_FAMILY (debian, redhat, arch, suse, alpine)
  → Sets OS_DISTRO (ubuntu, fedora, arch, etc.)
  → Sets OS_VERSION

# Filter scripts
yaml_os_compatible()
  → Check os_only (whitelist)
  → Check os_family (must match)
  → Check os_exclude (blacklist)
```

Only compatible scripts appear in menu.

---

## API Reference

### Core Library (lib/core.sh)

```bash
# Initialization
detect_os()              # Auto-detect Linux distribution

# Output Functions (all write to stderr)
msg()                    # Generic message
msg_ok()                 # Success message with ✓
msg_err()                # Error message with ✗
msg_warn()               # Warning message with ⚠
msg_info()               # Info message with ℹ
die()                    # Error message and exit 1

# Formatting
header()                 # Display formatted header
separator()              # Display line separator

# OS Info
show_os_info()           # Display detected OS
is_debian_based()        # Check if Debian family
is_redhat_based()        # Check if Red Hat family
is_arch_based()          # Check if Arch family
get_pkg_manager()        # Get package manager (apt, dnf, pacman, etc.)
has_sudo_access()        # Check sudo availability

# Debug
debug()                  # Print debug message (only if --debug)
```

### YAML Library (lib/yaml.sh)

```bash
# Configuration
yaml_load()              # Load YAML file (config or custom)

# Categories & Scripts
yaml_categories()        # Get all script categories
yaml_scripts()           # Get all script names
yaml_scripts_by_cat()    # Get scripts in category

# Script Info
yaml_info()              # Get script metadata
yaml_script_path()       # Get full path to script file
yaml_action_count()      # Get number of actions
yaml_action_name()       # Get action name
yaml_action_param()      # Get action parameter
yaml_action_description()# Get action description

# Prompts
yaml_prompt_count()      # Get number of prompts for action
yaml_prompt_field()      # Get prompt field (question, variable, type, default)
yaml_prompt_var()        # Get prompt variable name

# OS Compatibility
yaml_os_compatible()     # Check if script compatible with OS
```

### Menu Library (lib/menu.sh)

```bash
# Display
menu_show_main()         # Show main category menu
menu_show_category()     # Show scripts in category
menu_show_actions()      # Show actions for script
menu_show_custom()       # Show custom scripts

# Navigation
menu_main()              # Main menu loop
menu_category()          # Category selection loop
menu_actions()           # Action selection loop
menu_custom()            # Custom scripts loop

# Utilities
menu_valid_num()         # Validate number input
menu_error()             # Show error and wait
menu_confirm()           # Ask yes/no confirmation
```

### Execute Library (lib/execute.sh)

```bash
execute_action()         # Collect prompts, confirm, execute script
_prompt_by_type()        # Prompt with validation
```

---

## Troubleshooting

### Issue: Script not appearing in menu

**Checks:**
1. File exists in correct directory
   ```bash
   ls -la scripts/my_script.sh
   ls -la custom/my_script.sh
   ```

2. Script registered in YAML
   ```bash
   grep "my_script:" config.yaml
   grep "my_script:" custom.yaml
   ```

3. OS is compatible
   ```bash
   bash liauh.sh --debug
   # Check detected OS in output
   ```

4. custom.yaml has script_dir if in custom/
   ```yaml
   script_dir: custom  # Must be present
   ```

### Issue: Variables not passed to script

**Check:**
- Variable name in YAML matches what you use in script
  ```yaml
  variable: "DOMAIN"  # In config.yaml
  ```
  ```bash
  echo "$DOMAIN"      # In script
  ```

- Script is in correct directory per script_dir
  ```yaml
  # For scripts/ directory (system scripts)
  file: "my_script.sh"  # Default location
  
  # For custom/ directory (custom scripts)
  script_dir: custom
  file: "my_script.sh"  # In custom/ directory
  ```

### Issue: Colors not showing correctly

**Solution:** Ensure printf %b is used for ANSI codes

```bash
# Wrong (ANSI codes won't render):
echo "${C_GREEN}Success${C_RESET}"

# Correct (ANSI codes render properly):
printf "%b%s%b\n" "$C_GREEN" "Success" "$C_RESET"
```

### Issue: "No custom scripts available"

Happens when:
1. custom.yaml doesn't exist
2. custom/ directory doesn't exist
3. Scripts in custom.yaml have incompatible OS settings
4. Script files don't exist in custom/

**Fix:** Create custom.yaml and custom/ directory:
```bash
mkdir -p custom/
cp scripts/template.sh custom/my_script.sh
cat > custom.yaml << 'EOF'
script_dir: custom
scripts:
  my_script:
    description: "My custom script"
    category: "custom"
    file: "my_script.sh"
    needs_sudo: false
    actions:
      - name: "run"
        parameter: "run"
        prompts: []
EOF
```

### Issue: "yq not found/executable"

yq binaries are automatically made executable. If this fails:

**Check architecture:**
```bash
uname -m
# x86_64 → uses yq-amd64
# aarch64 → uses yq-arm64
# armv7l → uses yq-arm
# i686 → uses yq-386
```

**Verify file exists:**
```bash
ls -la lib/yq/
```

**Manual fix:**
```bash
chmod +x lib/yq/yq-amd64  # for x86_64
chmod +x lib/yq/yq-*      # for all
```

### Issue: Script fails with "Permission denied"

Scripts are made executable automatically, but if manual execution fails:

```bash
# Test outside LIAUH
bash scripts/my_script.sh install

# Check exit code
echo $?
```

### Issue: Sudo password keeps being asked

If your script calls `sudo` multiple times and each asks for password:

**Problem:** sudoers policy might not allow password caching

**Solution:** Sudo caches automatically - if it's not working:

1. Check sudoers policy:
   ```bash
   sudo -l  # Show sudo permissions
   sudo -v  # Test password cache
   ```

2. Your script doesn't need to do anything special:
   ```bash
   #!/bin/bash
   # LIAUH passed you as: sudo bash script.sh "install,DOMAIN=..."
   # Password is already cached by the initial sudo call
   
   sudo apt-get update      # No prompt
   sudo apt-get install pkg # No prompt (uses cached)
   ```

3. If sudo still prompts, ask your system admin to check:
   - sudoers `timestamp_timeout` setting (default 15 minutes)
   - `NOPASSWD` entries in sudoers

### Issue: "sudo: no password was provided" or auth failure

**Possible causes:**
1. User is not in sudoers
2. Sudo requires password but user is in NOPASSWD group
3. TTY issues in non-interactive environment

**Check sudo access:**
```bash
sudo -l  # List sudo permissions
sudo -n true  # Test passwordless sudo
```

**Test script with sudo:**
```bash
bash scripts/my_script.sh install  # Direct execution
sudo bash scripts/my_script.sh install  # With sudo
```

### Debug Mode

Run with debug output to see what's happening:

```bash
bash liauh.sh --debug 2>&1 | head -50
```

Output shows:
- Detected OS
- Config file loaded
- Category detection
- Script compatibility checks

---

## Best Practices

### Script Design

1. **Always support multiple actions**
   ```bash
   case "$ACTION" in
       install)  ;;
       remove)   ;;
       update)   ;;
       config)   ;;
   esac
   ```

2. **Use clear logging**
   ```bash
   log_info "Starting..."
   log_error "Failed: reason"
   log_success "Completed"
   ```

3. **Return proper exit codes**
   ```bash
   exit 0          # Success
   exit 1          # General error
   exit 2          # Misuse of shell command
   ```

4. **Parse LIAUH parameters correctly**
   
   LIAUH passes parameters as: `action,VAR1=val1,VAR2=val2,...`
   
   Always include the parsing code from template.sh:
   ```bash
   #!/bin/bash
   FULL_PARAMS="$1"
   ACTION="${FULL_PARAMS%%,*}"
   PARAMS_REST="${FULL_PARAMS#*,}"
   
   if [[ -n "$PARAMS_REST" && "$PARAMS_REST" != "$FULL_PARAMS" ]]; then
       while IFS='=' read -r key val; do
           [[ -n "$key" ]] && export "$key=$val"
       done <<< "${PARAMS_REST//,/$'\n'}"
   fi
   
   # Now use $DOMAIN, $PORT, etc. normally
   ```

### Configuration Design

1. **Use meaningful defaults**
   ```yaml
   - question: "Listen port?"
     variable: "PORT"
     type: "number"
     default: "80"           # Common default
   ```

2. **Group related scripts by category**
   ```yaml
   category: "database"
   category: "webserver"
   category: "security"
   ```

3. **Document with descriptions**
   ```yaml
   description: "Apache2 with SSL support"
   ```

4. **Set needs_sudo only when required**
   ```yaml
   # Only set if script REQUIRES root access
   # If omitted, defaults to false (optional field)
   needs_sudo: true   # Only for scripts that need root
   ```

### File Organization

1. **Keep scripts modular**
   - One script = one service/tool
   - Multiple actions = multiple ways to manage it

2. **No chmod needed**
   - Copy templates without chmod +x
   - LIAUH handles permissions

3. **Test outside LIAUH first**
   ```bash
   bash scripts/my_script.sh install
   ```

---

## Examples

### Example 1: Simple Install Script

**scripts/nginx.sh:**
```bash
#!/bin/bash
# Parse comma-separated parameters from LIAUH
FULL_PARAMS="$1"
ACTION="${FULL_PARAMS%%,*}"
PARAMS_REST="${FULL_PARAMS#*,}"

if [[ -n "$PARAMS_REST" && "$PARAMS_REST" != "$FULL_PARAMS" ]]; then
    while IFS='=' read -r key val; do
        [[ -n "$key" ]] && export "$key=$val"
    done <<< "${PARAMS_REST//,/$'\n'}"
fi

case "$ACTION" in
    install)
        echo "Installing Nginx for domain: $DOMAIN"
        sudo apt-get update
        sudo apt-get install -y nginx
        # Configure for $DOMAIN
        exit 0
        ;;
    remove)
        echo "Removing Nginx"
        sudo apt-get remove -y nginx
        exit 0
        ;;
esac
```

**In config.yaml:**
```yaml
nginx:
  description: "Nginx web server"
  category: "webserver"
  file: "nginx.sh"
  needs_sudo: true
  os_family: debian
  
  actions:
    - name: "install"
      parameter: "install"
      prompts:
        - question: "Server domain?"
          variable: "DOMAIN"
          type: "text"
          default: "example.com"
```

### Example 2: Multi-Action Script

**scripts/mysql.sh:**
```bash
#!/bin/bash
# Parse comma-separated parameters from LIAUH
FULL_PARAMS="$1"
ACTION="${FULL_PARAMS%%,*}"
PARAMS_REST="${FULL_PARAMS#*,}"

if [[ -n "$PARAMS_REST" && "$PARAMS_REST" != "$FULL_PARAMS" ]]; then
    while IFS='=' read -r key val; do
        [[ -n "$key" ]] && export "$key=$val"
    done <<< "${PARAMS_REST//,/$'\n'}"
fi

case "$ACTION" in
    install)
        echo "Installing MySQL..."
        echo "Root password: $MYSQL_ROOT_PASSWORD"
        sudo apt-get install -y mysql-server
        exit 0
        ;;
    remove)
        echo "Removing MySQL..."
        [[ "$KEEP_DATA" == "yes" ]] && echo "Keeping data"
        sudo apt-get remove -y mysql-server
        exit 0
        ;;
    backup)
        echo "Backing up to: $BACKUP_DIR"
        sudo mysqldump -u root -p$(cat /root/.my.cnf) --all-databases > "$BACKUP_DIR/backup.sql"
        exit 0
        ;;
esac
```

**In config.yaml:**
```yaml
mysql:
  description: "MySQL Database"
  category: "database"
  file: "mysql.sh"
  needs_sudo: true
  
  actions:
    - name: "install"
      parameter: "install"
      prompts:
        - question: "Root password?"
          variable: "MYSQL_ROOT_PASSWORD"
          type: "text"
          default: ""
    
    - name: "remove"
      parameter: "remove"
      prompts:
        - question: "Keep data?"
          variable: "KEEP_DATA"
          type: "yes/no"
          default: "yes"
    
    - name: "backup"
      parameter: "backup"
      prompts:
        - question: "Backup location?"
          variable: "BACKUP_DIR"
          type: "text"
          default: "/backups"
```

---

## Version

LIAUH v1.0 - 2025

---

## Summary

✅ **No chmod +x needed** - LIAUH handles permissions
✅ **Variables auto-exported** - Access via $VARIABLE_NAME
✅ **OS auto-detected** - Scripts filtered by compatibility
✅ **Prompts validated** - Input type checking (text/yes-no/number)
✅ **Sudo handled** - Automatic privilege escalation
✅ **Fully documented** - Comments in English
✅ **Easy to extend** - Template provided, just register in YAML

For updates and contributions, check the repository.

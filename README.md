# LIAUH - Linux Install and Update Helper

**Interactive menu system for managing system installation and update scripts**

## 🚀 Installation

### Option 1: One-liner with wget (Recommended)
```bash
wget -qO - https://raw.githubusercontent.com/sorglos-it/liauh/main/install.sh | bash && ./liauh/liauh.sh
```

### Option 2: One-liner with curl
```bash
curl -sSL https://raw.githubusercontent.com/sorglos-it/liauh/main/install.sh | bash && ./liauh/liauh.sh
```

### Option 3: Git Clone
```bash
git clone https://github.com/sorglos-it/liauh.git
cd liauh && bash liauh.sh
```

### Option 4: Manual Install
```bash
sudo apt-get update && sudo apt-get install -y git
cd ~ && git clone https://github.com/sorglos-it/liauh.git
cd liauh && bash liauh.sh
```

## 📖 Usage

### Start the Interactive Menu
```bash
bash liauh.sh
```
Displays a menu of available scripts (system & custom). Select one to run.

### Command Line Options

```bash
bash liauh.sh                # Start menu (auto-updates)
bash liauh.sh --no-update    # Start without checking for updates
bash liauh.sh --debug        # Enable debug/verbose output
bash liauh.sh --check-update # Check for updates (don't apply)
bash liauh.sh --update       # Apply updates manually
```

## ✨ Features

- **Interactive Menu** - Easy navigation for non-technical users
- **OS Detection** - Supports Debian, Red Hat, Arch, SUSE, Alpine, Proxmox
- **Auto-Update** - Keeps LIAUH scripts current from GitHub
- **Multi-Repo Support** - Clone multiple custom script repositories with auto-updates
- **Flexible Authentication** - SSH keys, Personal Access Tokens, or public repos
- **SSH Key Management** - Store keys in `custom/keys/` (never committed)
- **Interactive Prompts** - Text input, yes/no questions, number selection
- **Sudo Caching** - Password prompted once per session (~15 min reuse)
- **No Dependencies** - Works with bash, git, and standard tools
- **13 System Scripts** - Pre-built scripts for common Linux management tasks

## 🔧 Configuration

### System Scripts
Define scripts in `config.yaml` (read-only, updated from GitHub):
```yaml
scripts:
  my-script:
    description: "What this script does"
    path: scripts/my-script.sh
    os_family: [debian, redhat]  # Optional: limit to specific OS
    needs_sudo: true              # Optional: set if needs root
```

### Custom Script Repositories (Multi-Repo Hub)

LIAUH supports **multiple custom script repositories** via `custom/repo.yaml`. Each repository is cloned to `custom/` and auto-updated on startup.

#### Quick Setup: SSH with Keys in custom/keys/

**1. Add your SSH key to the keys directory:**
```bash
# Copy your GitHub SSH key
cp ~/.ssh/id_rsa liauh/custom/keys/id_rsa
chmod 600 liauh/custom/keys/id_rsa
```

**2. Configure repository in `custom/repo.yaml`:**
```yaml
repositories:
  my-scripts:
    name: "My Scripts"
    url: "git@github.com:org/my-scripts.git"
    path: "my-scripts"              # Auto-prefixed with custom/
    auth_method: "ssh"
    ssh_key: "id_rsa"               # Filename in custom/keys/
    enabled: true
    auto_update: true
```

**3. Create `custom/my-scripts/custom.yaml`:**
```yaml
scripts:
  my-tool:
    description: "My custom tool"
    path: scripts/my-tool.sh
    needs_sudo: false
```

#### Other Authentication Methods

**HTTPS with Personal Access Token:**
```yaml
repositories:
  github-repo:
    url: "https://github.com/org/repo.git"
    path: "github-repo"
    auth_method: "https_token"
    token: "${LIAUH_TOKEN}"         # Set environment variable first
    enabled: true
    auto_update: true
```

**Environment Setup:**
```bash
export LIAUH_TOKEN="ghp_xxxxxxxxxxxx"
bash liauh.sh
```

**Public Repository (no auth):**
```yaml
repositories:
  public-addons:
    url: "https://github.com/org/public-repo.git"
    path: "public-addons"
    auth_method: "none"
    enabled: true
    auto_update: false
```

#### Disable Auto-Update for Read-Only Repos

```yaml
repositories:
  company-standards:
    url: "..."
    path: "company-standards"
    enabled: true
    auto_update: false              # Won't update automatically
```

See **[custom/repo.yaml](custom/repo.yaml)** for complete documentation.

## 📚 Documentation

- **README.md** - This file (quick start)
- **DOCS.md** - Complete documentation with architecture & examples
- **LICENSE** - MIT License (free for commercial & personal use)

## 🏗️ Project Structure

```
liauh/
├── liauh.sh              # Main entry point (auto-updates self)
├── config.yaml           # System scripts (auto-updated from GitHub)
├── lib/                  # Library functions
│   ├── core.sh
│   ├── yaml.sh
│   ├── menu.sh
│   ├── execute.sh
│   ├── repos.sh          # Repository management
│   └── yq/               # YAML parser binaries (auto-installed)
├── scripts/              # System scripts (13 production + 2 reference)
├── custom/               # Custom repository hub (local, not in git)
│   ├── repo.yaml         # Configure custom repositories
│   ├── keys/             # SSH private keys (never committed)
│   │   └── .gitignore
│   ├── custom-scripts/   # Cloned repo 1 (auto-pulled)
│   ├── company-tools/    # Cloned repo 2 (auto-pulled)
│   └── ...               # More cloned repos
├── README.md             # This file (quick start)
├── DOCS.md               # Complete documentation
├── SCRIPTS.md            # Available scripts reference
├── CHANGES.md            # Version history
└── LICENSE               # MIT License
```

## 💻 System Requirements

- Linux (Debian, Red Hat, Arch, SUSE, Alpine, or compatible)
- Bash 4.0+
- Git (for auto-update)
- `sudo` access (if scripts need root)

## 📝 License

MIT License - Free for commercial and personal use

**Author:** Thomas Weirich (Sorglos IT)

See [LICENSE](LICENSE) for full details.

## 🆘 Troubleshooting

### "Permission denied" on liauh.sh
```bash
chmod +x liauh.sh
bash liauh.sh
```
(Usually not needed - auto-handled on first run)

### Password keeps getting asked
This is normal - LIAUH caches your sudo password for ~15 minutes.

### Update not working
```bash
bash liauh.sh --update
```
If offline, LIAUH continues anyway.

### Custom repositories not cloning
**Check SSH key:**
```bash
# Verify key exists and has correct permissions
ls -la liauh/custom/keys/id_rsa
chmod 600 liauh/custom/keys/id_rsa

# Verify SSH access
ssh -i liauh/custom/keys/id_rsa -T git@github.com
```

**Check repository configuration:**
- Verify URL is correct in `custom/repo.yaml`
- Ensure `enabled: true` is set
- Check that repository is accessible with your credentials

**Manual clone test:**
```bash
cd liauh/custom/
git clone git@github.com:org/repo.git test-repo
```

### Custom scripts not showing in menu
- Verify repository is in `custom/repo.yaml` with `enabled: true`
- Check that `custom.yaml` exists in cloned repo with script definitions
- Verify script path is correct: `path: "scripts/script-name.sh"`
- Check OS compatibility: ensure your distro matches script's `os_family`

### SSH key passphrase prompt
If your SSH key is encrypted:
```bash
# Set passphrase in environment
export SSH_KEY_PASSPHRASE="your-passphrase"
bash liauh.sh
```

---

## 📋 Available Scripts

See **[SCRIPTS.md](SCRIPTS.md)** for the complete list of all available system scripts and their actions.

---

## 💝 Support & Donate

If you find LIAUH helpful, please consider supporting its development!

[![PayPal Donate](https://img.shields.io/badge/PayPal-Donate-blue?style=for-the-badge&logo=paypal)](https://www.paypal.com/donate/?hosted_button_id=9U6NJRGR7SE52)

Your support helps maintain and improve LIAUH. Thank you! 🙏

---

**Questions?** See **DOCS.md** for detailed documentation.

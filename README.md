# LIAUH - Linux Install and Update Helper

**Interactive menu system for managing system installation and update scripts**

## 🚀 Installation

### Option 1: Simple Clone (Recommended)
```bash
git clone https://github.com/sorglos-it/liauh.git
cd liauh && bash liauh.sh
```

### Option 2: One-liner with wget
```bash
wget -qO - https://raw.githubusercontent.com/sorglos-it/liauh/main/install.sh | bash
```

### Option 3: One-liner with curl
```bash
curl -sSL https://raw.githubusercontent.com/sorglos-it/liauh/main/install.sh | bash
```

### Option 4: Manual
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
- **OS Detection** - Supports Debian, Red Hat, Arch, SUSE, Alpine
- **Auto-Update** - Keeps scripts current from GitHub
- **Custom Scripts** - Add your own scripts to `custom.yaml`
- **Interactive Prompts** - Text input, yes/no questions, number selection
- **Sudo Caching** - Password prompted once per session
- **No Dependencies** - Works with bash, git, and standard tools

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

### Custom Scripts
Create your own scripts in `custom.yaml` (never overwritten by updates):
```yaml
scripts:
  my-custom:
    description: "My custom script"
    path: custom/my-script.sh
    needs_sudo: false
```

## 📚 Documentation

- **README.md** - This file (quick start)
- **DOCS.md** - Complete documentation with architecture & examples
- **LICENSE** - MIT License (free for commercial & personal use)

## 🏗️ Project Structure

```
liauh/
├── liauh.sh              # Main entry point
├── lib/                  # Libraries (colors, menus, YAML, etc.)
├── scripts/              # System scripts
├── custom/               # Your custom scripts (not tracked)
├── config.yaml           # System script definitions
├── custom.yaml           # Your custom script definitions (not tracked)
├── README.md             # This file
├── DOCS.md               # Full documentation
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

### Custom scripts not showing
Make sure `custom.yaml` is in the liauh directory and script path is correct.

---

**Questions?** See **DOCS.md** for detailed documentation.

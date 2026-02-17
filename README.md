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

## 📋 Available Scripts

| Script | Category | Supported OS | Actions |
|--------|----------|--------------|---------|
| **linux** | System | Debian, Red Hat, Arch, SUSE, Alpine (not Proxmox) | `network` (DHCP/static), `dns`, `hostname`, `user-add`, `user-delete`, `user-password`, `group-create`, `user-to-group` |
| **proxmox** | System | Proxmox VE | `stop-all` (VMs/LXC), `language`, `qemu-guest-agent`, `lxc-ssh-root`, `lxc-to-template`, `template-to-lxc`, `unlock-lxc` |
| **debian** | System Updates | Debian | `update` (system update to latest version) |
| **ubuntu** | System Updates | Ubuntu | `update` (system upgrade), `ubuntu-pro` (attach subscription), `detach` (remove subscription) |
| **ca-cert-update** | Security | Debian, Red Hat | `update` (install CA certificate from server) |
| **pikvm-v3** | System Updates | Arch (PiKVM v3) | `update`, `mount-iso`, `dismount-iso`, `oled-enable`, `vnc-enable`, `vnc-user`, `rtc-enable` (Geekworm), `hostname`, `atx-disable`, `create-usb-img`, `setup` (SSL certificate) |
| **compression** | Tools | Debian, Red Hat, Arch, SUSE, Alpine | `install` (zip/unzip), `uninstall` (zip/unzip) |
| **mariadb** | Database | Debian, Red Hat | `install`, `update`, `uninstall`, `config` (max connections, buffer pool, bind address, charset) |
| **docker** | Tools | Debian, Red Hat, Arch | `install`, `update`, `uninstall`, `config` (storage driver, log driver, registry mirror, concurrent downloads) |
| **apache** | Webserver | Debian, Red Hat, Arch, SUSE, Alpine | `install`, `update`, `uninstall`, `vhosts` (virtual hosts), `default` (server admin, modules), `config` (performance, logging) |
| **nginx** | Webserver | Debian, Red Hat, Arch, SUSE, Alpine | `install`, `update`, `uninstall`, `vhosts` (server blocks), `default` (gzip, client max body, hide version), `config` (worker processes, connections, logging) |
| **portainer** | Tools | Debian, Red Hat, Arch, SUSE, Alpine | `install` (Docker UI), `update`, `uninstall` |
| **portainer-client** | Tools | Debian, Red Hat, Arch, SUSE, Alpine | `install` (Agent/Edge), `update`, `uninstall` |
| **nodejs** | Programming Languages | All | `install` (with version), `update`, `uninstall`, `config` |
| **python** | Programming Languages | All | `install` (with version), `update`, `uninstall`, `config` |
| **ruby** | Programming Languages | All | `install` (with version), `update`, `uninstall`, `config` |
| **golang** | Programming Languages | All | `install`, `update`, `uninstall`, `config` |
| **php** | Programming Languages | All | `install` (with Composer option), `update`, `uninstall`, `composer` (standalone), `config` |
| **perl** | Programming Languages | All | `install`, `update`, `uninstall`, `cpan-module`, `config` |

**Legend:**
- **Debian:** Ubuntu, Debian, Linux Mint, etc.
- **Red Hat:** CentOS, RHEL, Fedora, etc.
- **Arch:** Arch Linux, Manjaro, etc.
- **SUSE:** openSUSE, SUSE Linux, etc.
- **Alpine:** Alpine Linux (lightweight)

**Note:** This list is automatically maintained. Check back for new scripts!

---

## 💝 Support & Donate

If you find LIAUH helpful, please consider supporting its development!

[![PayPal Donate](https://img.shields.io/badge/PayPal-Donate-blue?style=for-the-badge&logo=paypal)](https://www.paypal.com/donate/?hosted_button_id=9U6NJRGR7SE52)

Your support helps maintain and improve LIAUH. Thank you! 🙏

---

**Questions?** See **DOCS.md** for detailed documentation.

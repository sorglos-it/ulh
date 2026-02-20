# ulh - Unknown Linux Helper

**v0.5** | 45 system management scripts for all Linux distributions

## 🚀 Installation

### One-liner (Auto-install wget)
```bash
wget -qO - https://raw.githubusercontent.com/sorglos-it/ulh/main/install.sh | bash && cd ~/ulh && bash ulh.sh
```
### One-liner (Auto-install curl)
```bash
curl -sSL https://raw.githubusercontent.com/sorglos-it/ulh/main/install.sh | bash && cd ~/ulh && bash ulh.sh
```

### Manual Install
```bash
git clone https://github.com/sorglos-it/ulh.git
cd ulh
bash ulh.sh
```

## ✨ Features

- **Multi-Distribution** - Debian, Ubuntu, Red Hat, Arch, SUSE, Alpine, Proxmox
- **45 Scripts** - Network, system management, web servers, databases, languages, tools
- **Auto-Updates** - Self-updates on startup with transparent restart
- **Custom Repos** - Clone your own script repositories with git authentication
- **Interactive Menu** - Clean, intuitive box-based CLI interface
- **All Distros** - Every script supports all 5 major distribution families
- **Zero Dependencies** - Just bash, git, and standard Linux tools

## 📖 Usage

```bash
cd ~/ulh
bash ulh.sh
```

Menu flow:
```
1. Repository Selector
   ├─ ulh Scripts
   │  └─ Categories
   │     └─ Scripts
   │        └─ Actions
   └─ Custom Repos
      └─ Scripts
         └─ Actions
```

## 🛠️ System Scripts (45)

See **[SCRIPTS.md](SCRIPTS.md)** for complete reference.

## 🔧 Custom Repositories

Add your own scripts with git authentication (SSH, Token, Basic Auth):

```yaml
# custom/repo.yaml
repositories:
  my-scripts:
    name: "My Custom Scripts"
    url: "git@github.com:user/my-scripts.git"
    path: "my-scripts"
    auth_method: "ssh"
    enabled:
```

See **[DOCS.md](DOCS.md#custom-repositories)** for setup.

## 🏗️ Architecture

```
ulh/
├── ulh.sh              # Entry point (self-updating)
├── lib/                  # 7 focused libraries
├── scripts/              # 45 system management scripts + custom repos
├── custom/               # Your custom repos
├── config.yaml           # System scripts config
├── README.md            # This file
├── DOCS.md              # Comprehensive guide
└── SCRIPTS.md           # Script reference
```

## 📚 Documentation

- **[DOCS.md](DOCS.md)** - Complete guide: architecture, configuration, templates, troubleshooting
- **[SCRIPTS.md](SCRIPTS.md)** - All 45 scripts with categories and descriptions

## 🖥️ Supported Distributions

- ✅ Debian / Ubuntu / Linux Mint
- ✅ Red Hat / Fedora / CentOS / Rocky / AlmaLinux
- ✅ Arch / Manjaro
- ✅ SUSE / openSUSE
- ✅ Alpine
- ✅ Proxmox VE
- ⚠️ PiKVM v3 (Arch-based appliance, limited package management)

## 💾 Requirements

- Linux (any major distro)
- Bash 4.0+
- Git
- `sudo` access (for system-level operations)

## 🚀 Quick Start

1. **Install**: `bash install.sh` or clone repo
2. **Run**: `bash ulh.sh`
3. **Select**: Choose System Management or Custom Repo
4. **Navigate**: Category → Script → Action
5. **Configure**: Follow prompts (or accept defaults)

## 🔐 Security

- Scripts run **individually with sudo** (ulh stays unprivileged)
- SSH keys stored in **custom/keys/** (protected by .gitignore)
- No hardcoded credentials (use environment variables)
- All scripts pass **syntax validation** (bash -n)

## 📝 Creating Custom Scripts

To add scripts to your custom repository:

```bash
mkdir -p custom/myrepo/scripts
cp scripts/_template.sh custom/myrepo/scripts/my-script.sh
```

See **[DOCS.md - Script Development](DOCS.md#script-development)** for detailed guide and how to integrate custom repositories.

## 🤝 Contributing

Contributions welcome! See **[DOCS.md](DOCS.md)** for script development guidelines.

## 📄 License

MIT License - Free for personal and commercial use

---

**Questions?** Check **[DOCS.md](DOCS.md)** or open an issue on GitHub.

## 💝 Support ulh

If ulh helps you save time and reduces your Linux headaches, consider supporting the project:

[![Donate with PayPal](https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif)](https://www.paypal.com/donate/?hosted_button_id=6CDEVZGJWTNQQ)

## 📖 The Story Behind ulh

Curious how "Unknown Linux Helper" came to be? Read **[BACKSTORY.md](BACKSTORY.md)** — the chaotic naming odyssey featuring Kevin, the Unknown Man, and why naming things is impossible.

---

**GitHub**: https://github.com/sorglos-it/ulh

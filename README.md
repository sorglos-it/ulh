# LIAUH - Linux Install and Update Helper

**v0.4+** | 45 system management scripts for all Linux distributions

## 🚀 Installation

### One-liner (Auto-install)
```bash
wget -qO - https://raw.githubusercontent.com/sorglos-it/liauh/main/install.sh | bash && cd ~/liauh && bash liauh.sh
curl -sSL https://raw.githubusercontent.com/sorglos-it/liauh/main/install.sh | bash && cd ~/liauh && bash liauh.sh
```

### Manual Install
```bash
git clone https://github.com/sorglos-it/liauh.git
cd liauh
bash liauh.sh
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
cd ~/liauh
bash liauh.sh
```

Menu flow:
```
1. Repository Selector
   ├─ LIAUH Scripts
   │  └─ Categories
   │     └─ Scripts
   │        └─ Actions
   └─ Custom Repos
      └─ Scripts
         └─ Actions
```

## 🛠️ System Scripts (45)

### Essential Tools (11)
curl, wget, git, vim, nano, htop, tmux, screen, build-essential, jq, locate

### Webservers (2)
Apache, Nginx

### Databases (3)
MariaDB, PostgreSQL, MySQL

### Containerization & VM (4)
Docker, Portainer, Docker Compose, Proxmox

### Programming Languages (6)
Node.js, Python, Ruby, Go, PHP, Perl

### Logging & Monitoring (4)
rsyslog, syslog-ng, fail2ban, logrotate

### Networking (10)
OpenSSH, net-tools, bind-utils, WireGuard, OpenVPN, UFW, Pi-hole, AdGuard Home, Samba, cifs-utils

### System Management (5)
Linux (network, DNS, users, groups), Ubuntu, Debian, PiKVM v3, Remotely

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
    enabled: true
    auto_update: false
```

See **[DOCS.md](DOCS.md#custom-repositories)** for setup.

## 🏗️ Architecture

```
liauh/
├── liauh.sh              # Entry point (self-updating)
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
2. **Run**: `bash liauh.sh`
3. **Select**: Choose System Management or Custom Repo
4. **Navigate**: Category → Script → Action
5. **Configure**: Follow prompts (or accept defaults)

## 🔐 Security

- Scripts run **individually with sudo** (LIAUH stays unprivileged)
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

**GitHub**: https://github.com/sorglos-it/liauh

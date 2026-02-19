# LIAUH - Project Memory

**v0.4** | 45 production scripts with unified system management framework

## Current Status

- **Status**: Stable & Maintained
- **Scripts**: 45 system management scripts
- **Last Update**: 2026-02-18

## Architecture

```
liauh/
├── liauh.sh              # Main entry point (auto-updating, 945 lines)
├── lib/                  # 7 focused libraries
│   ├── core.sh          # OS detection, logging, utilities
│   ├── colors.sh        # ANSI color definitions
│   ├── yaml.sh          # YAML parsing via yq binary
│   ├── menu.sh          # Menu display + navigation
│   ├── execute.sh       # Script execution engine
│   └── repos.sh         # Repository sync + management
├── scripts/             # 45 system management scripts
├── custom/              # User repositories (git-ignored except repo.yaml)
├── config.yaml          # System scripts configuration
├── README.md            # Quick start guide
├── DOCS.md              # Comprehensive documentation
├── SCRIPTS.md           # Script reference table
└── MEMORY.md            # Project memory (this file)
```

## Supported Distributions

- ✅ Debian / Ubuntu / Linux Mint
- ✅ Red Hat / Fedora / CentOS / Rocky / AlmaLinux
- ✅ Arch / Manjaro
- ✅ SUSE / openSUSE
- ✅ Alpine
- ✅ Proxmox VE
- ✅ PiKVM v3

## v0.4 - 45 Scripts Implemented & Tested

### Script Categories (8 Categories)

1. **Essential Tools** (11)
   - curl, wget, git, vim, nano, htop, tmux, screen, build-essential, jq, locate

2. **Webservers** (2)
   - Apache, Nginx

3. **Databases** (3)
   - MariaDB, PostgreSQL, MySQL

4. **Containerization & VM** (4)
   - Docker, Portainer, Docker Compose, Proxmox (7 actions: install, update, uninstall, make-lxc-to-template, make-template-to-lxc, unlock-vm, stop-all)

5. **Programming Languages** (6)
   - Node.js, Python, Ruby, Go, PHP, Perl

6. **Logging & Monitoring** (4)
   - rsyslog, syslog-ng, fail2ban, logrotate

7. **Networking** (10)
   - OpenSSH, net-tools, bind-utils, WireGuard, OpenVPN, UFW, Pi-hole, AdGuard Home, Samba, cifs-utils

8. **System Management** (5)
   - Linux (network, DNS, users, groups), Ubuntu, Debian, PiKVM v3, Remotely

### Testing Status
- **Total Scripts**: 45
- **Tested**: 45/45 ✓
- **All Distro Support**: 5 major families covered

## Key Features

- **Multi-Distribution Support** - All scripts work on Debian, Red Hat, Arch, SUSE, Alpine
- **Auto-Updates** - Self-updates on startup with transparent restart
- **Custom Repositories** - Clone your own script repositories with git authentication
- **Interactive Menu** - Clean, intuitive box-based CLI interface
- **Zero Dependencies** - Just bash, git, and standard Linux tools
- **Syntax Validation** - All scripts pass bash -n checks
- **Focused Libraries** - Each file handles one responsibility

## Development Guidelines

- Use the template: `scripts/_template.sh`
- Support all 5 distribution families
- Proper error handling with logging functions
- Service management with systemctl
- Parameter parsing via comma-separated format
- Clean formatting and descriptive variable names

## Database Support

- **MariaDB** - Supported on Debian, Red Hat
- **PostgreSQL** - All 5 distribution families
- **MySQL** - All 5 distribution families

All database scripts support: install, update, uninstall, config actions

## Custom Repository Support

- SSH authentication (recommended)
- HTTPS token-based auth
- HTTPS basic auth
- Public (no auth)

SSH keys stored in `custom/keys/` (protected by .gitignore)

## Known Capabilities

- Self-updating without user interaction
- Clean menu system with consistent 80-char formatting
- Repository auto-sync on startup (configurable)
- Flexible prompt system (text, yes/no, number types)
- Context-aware menus with proper navigation

## Recent Changes (v0.4+)

- Added locate fast file search utility (indexed database)
- Updated Essential Tools category: 10 → 11 scripts
- Added cifs-utils for SMB/CIFS share mounting
- Updated Networking category: 9 → 10 scripts
- Added Remotely remote desktop and support software
- Updated System Management category: 5 → 6 scripts
- Total script count: 43 → 44 → 45
- Enhanced networking, file sharing, and remote support capabilities
- **Proxmox Rewrite (v0.5+)**:
  - Complete rewrite from Proxmox VE server installation to guest agent + container management
  - For guests: qemu-guest-agent installation/update/uninstall with multi-distro support
  - For hosts: VM/LXC container operations (make-lxc-to-template, make-template-to-lxc, unlock-vm, stop-all)
  - Proxmox now supports 7 actions: install, update, uninstall, make-lxc-to-template, make-template-to-lxc, unlock-vm, stop-all
  - All prompts properly integrated for CTID input
  - Comprehensive error handling and validation
- All documentation updated

## Security Notes

- Scripts run individually with sudo (LIAUH stays unprivileged)
- SSH keys stored in custom/keys/ (git-ignored)
- No hardcoded credentials (environment variables)
- All scripts syntax-checked before execution

## References

- **GitHub**: https://github.com/sorglos-it/liauh
- **Docs**: [DOCS.md](DOCS.md)
- **Scripts**: [SCRIPTS.md](SCRIPTS.md)
- **License**: MIT

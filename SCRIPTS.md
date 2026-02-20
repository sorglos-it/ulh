# ulh Scripts Reference

**v0.5** | Complete catalog of 45 system management scripts

All scripts support **install**, **update**, **uninstall**, and **config** actions (where applicable).

---

## Script Categories (8 Categories, 45 Scripts)

ulh organizes scripts into 8 logical categories:

1. **Essential Tools** (11)
2. **Webservers** (2)
3. **Databases** (3)
4. **Containerization & VM** (4)
5. **Programming Languages** (6)
6. **Logging & Monitoring** (4)
7. **Networking** (10)
8. **System Management** (5)

---

## Essential Tools (11)

Core utilities for system administration and development:

| Script | Description | Supports |
|--------|-------------|----------|
| **curl** | HTTP/HTTPS requests utility | All 5 distros |
| **wget** | HTTP/FTP downloads utility | All 5 distros |
| **git** | Distributed version control system | All 5 distros |
| **vim** | Advanced text editor | All 5 distros |
| **nano** | Simple text editor | All 5 distros |
| **htop** | Interactive system resource monitor | All 5 distros |
| **tmux** | Terminal multiplexer | All 5 distros |
| **screen** | Terminal multiplexer | All 5 distros |
| **build-essential** | Development tools and compilers | All 5 distros |
| **jq** | JSON query processor | All 5 distros |
| **locate** | Fast file search using indexed database | All 5 distros |

---

## Webservers (2)

Web application and static content servers:

| Script | Description | Supports |
|--------|-------------|----------|
| **apache** | Apache HTTP Server | All 5 distros |
| **nginx** | Nginx HTTP Server | All 5 distros |

---

## Databases (3)

Data persistence and management:

| Script | Description | Supports |
|--------|-------------|----------|
| **mariadb** | MariaDB relational database server | Debian, Red Hat |
| **postgres** | PostgreSQL relational database | All 5 distros |
| **mysql** | MySQL relational database | All 5 distros |

---

## Containerization & VM (4)

Container runtime, VM management, and orchestration platforms:

| Script | Description | Supports |
|--------|-------------|----------|
| **docker** | Docker container runtime | All 5 distros |
| **portainer** | Portainer container management UI | All 5 distros |
| **docker-compose** | Docker Compose multi-container orchestration | All 5 distros |
| **proxmox** | Proxmox guest agent and container management (install, update, uninstall, make-lxc-to-template, make-template-to-lxc, unlock-vm, stop-all, list-lxc, list-lxc-running, start-vm, stop-vm, start-lxc, stop-lxc) | Proxmox only |

---

## Programming Languages (6)

Runtime environments and interpreters:

| Script | Description | Supports |
|--------|-------------|----------|
| **nodejs** | Node.js JavaScript runtime + npm | All 5 distros |
| **python** | Python 3 interpreter + pip | All 5 distros |
| **ruby** | Ruby interpreter + gem package manager | All 5 distros |
| **golang** | Go programming language compiler | All 5 distros |
| **php** | PHP interpreter + CLI | All 5 distros |
| **perl** | Perl interpreter + modules | All 5 distros |

---

## Logging & Monitoring (4)

System logging, log management, and security monitoring:

| Script | Description | Supports |
|--------|-------------|----------|
| **rsyslog** | System logging daemon | All 5 distros |
| **syslog-ng** | Advanced system logging engine | All 5 distros |
| **fail2ban** | Brute-force attack protection | All 5 distros |
| **logrotate** | Log rotation and compression utility | All 5 distros |

---

## Networking (10)

Network tools, VPN, DNS ad-blocking, file sharing, and connectivity:

| Script | Description | Supports |
|--------|-------------|----------|
| **openssh** | SSH server and client for secure remote access | All 5 distros |
| **net-tools** | Network utilities (ifconfig, netstat) | All 5 distros |
| **bind-utils** | DNS tools (dig, nslookup, host) | All 5 distros |
| **wireguard** | Modern, high-performance VPN protocol | All 5 distros |
| **openvpn** | Open-source VPN tunneling solution | All 5 distros |
| **ufw** | Uncomplicated Firewall for network security | All 5 distros |
| **pihole** | Pi-hole DNS ad-blocking service | All 5 distros |
| **adguard-home** | AdGuard Home DNS ad-blocking service | All 5 distros |
| **samba** | Network file sharing with Samba/SMB protocol | All 5 distros |
| **cifs-utils** | Mount and manage SMB/CIFS network shares | All 5 distros |

---

## System Management (5)

OS-level management and specialized appliances:

| Script | Description | Supports |
|--------|-------------|----------|
| **linux** | Core Linux system configuration (network, DNS, users, groups, CA certs) | All 5 distros |
| **ubuntu** | Ubuntu-specific system management | Ubuntu only |
| **debian** | Debian-specific system management | Debian only |
| **pikvm-v3** | PiKVM v3 appliance configuration and management | Arch (PiKVM) only |
| **remotely** | Remotely remote desktop and support software | Debian, Ubuntu, RHEL, CentOS, Rocky, Alma, Fedora, openSUSE, SLES, Amazon Linux |

---

## Distribution Support Matrix

| Distro | Supports | Package Manager |
|--------|----------|-----------------|
| Debian | All scripts | apt-get |
| Ubuntu | All scripts | apt-get |
| Red Hat/Fedora/CentOS | All scripts | dnf/yum |
| Arch/Manjaro | All scripts | pacman |
| SUSE/openSUSE | All scripts | zypper |
| Alpine | Most scripts | apk |
| Proxmox VE | All scripts | apt-get |

---

## Quick Start Examples

### Install Node.js
From ulh menu:
1. Select **Programming Languages** category
2. Select **nodejs** script
3. Choose **install** action
4. Follow configuration prompts

### Configure Linux Network
From ulh menu:
1. Select **System Management** category
2. Select **linux** script
3. Choose **network** or **dns** action
4. Enter interface name (eth0) and IP settings

### Install MariaDB
From ulh menu:
1. Select **Databases** category
2. Select **mariadb** script
3. Choose **install** action
4. Provide root password when prompted

---

## Creating Your Own Scripts

See **[DOCS.md - Script Development](DOCS.md#script-development)** for:
- Using the template (`scripts/_template.sh`)
- Parameter parsing format
- Multi-distribution support
- Best practices and guidelines

---

**For detailed documentation:** See [DOCS.md](DOCS.md)
**For quick start:** See [README.md](README.md)

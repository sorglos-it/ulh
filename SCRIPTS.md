# LIAUH Scripts Reference

**v0.3** | Complete catalog of 60+ system management scripts

All scripts support **install**, **update**, **uninstall**, and **config** actions (where applicable).

---

## Menu Structure (5 Categories)

LIAUH menu organized into 5 main categories:

1. **Database**
2. **Programming Languages**
3. **System**
4. **Tools**
5. **Webserver**

---

## Database

| Script | Description | Supports |
|--------|-------------|----------|
| **mariadb** | MariaDB database server | Debian, Red Hat |

---

## Programming Languages

| Script | Description | Supports |
|--------|-------------|----------|
| **nodejs** | Node.js + npm | All 5 distros |
| **python** | Python 3 + pip | All 5 distros |
| **ruby** | Ruby + gem | All 5 distros |
| **golang** | Go programming language | All 5 distros |
| **php** | PHP + cli | All 5 distros |
| **perl** | Perl + modules | All 5 distros |

---

## System

Essential tools and system management:

| Script | Description | Supports |
|--------|-------------|----------|
| **curl** | HTTP/HTTPS requests | All 5 distros |
| **wget** | HTTP/FTP downloads | All 5 distros |
| **git** | Version control system | All 5 distros |
| **vim** | Advanced text editor | All 5 distros |
| **nano** | Simple text editor | All 5 distros |
| **htop** | System resource monitor | All 5 distros |
| **tmux** | Terminal multiplexer | All 5 distros |
| **screen** | Terminal multiplexer | All 5 distros |
| **openssh** | SSH server/client | All 5 distros |
| **net-tools** | Network utilities | All 5 distros |
| **build-essential** | Dev tools & compilers | All 5 distros |
| **jq** | JSON query processor | All 5 distros |
| **ufw** | Uncomplicated Firewall | All 5 distros |
| **linux** | Network, DNS, users, groups, CA certs | All 5 distros |
| **ubuntu** | Ubuntu-specific management | Ubuntu only |
| **debian** | Debian-specific management | Debian only |
| **proxmox** | Proxmox VE management | Proxmox only |
| **pikvm-v3** | PiKVM v3 appliance management | Arch (PiKVM) only |

---

## Tools

Logging, monitoring, networking, and utilities:

| Script | Description | Supports |
|--------|-------------|----------|
| **rsyslog** | System logging daemon | All 5 distros |
| **syslog-ng** | Advanced system logging | All 5 distros |
| **fail2ban** | Brute-force attack protection | All 5 distros |
| **logrotate** | Log rotation utility | All 5 distros |
| **bind-utils** | DNS tools (dig, nslookup) | All 5 distros |
| **wireguard** | Modern VPN protocol | All 5 distros |
| **openvpn** | OpenVPN tunneling | All 5 distros |
| **docker** | Docker container runtime | All 5 distros |
| **portainer** | Container management UI | All 5 distros |

---

## Webserver

| Script | Description | Supports |
|--------|-------------|----------|
| **apache** | Apache HTTP Server | All 5 distros |
| **nginx** | Nginx HTTP Server | All 5 distros |

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

## Usage Examples

### Install Node.js
From menu: **System** → **Programming Languages** → **nodejs** → **install**

### Configure Network
From menu: **System** → **System** → **linux** → **network**
- Enter interface name (eth0)
- Choose DHCP or static IP

### Install MariaDB
From menu: **Database** → **Database** → **mariadb** → **install**
- Optional prompts for configuration

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

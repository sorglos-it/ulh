# Available Scripts

Complete reference of all LIAUH system scripts and their actions.

## Overview

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

## Legend

- **Debian:** Ubuntu, Debian, Linux Mint, etc.
- **Red Hat:** CentOS, RHEL, Fedora, etc.
- **Arch:** Arch Linux, Manjaro, etc.
- **SUSE:** openSUSE, SUSE Linux, etc.
- **Alpine:** Alpine Linux (lightweight)

## Notes

- This list is automatically maintained. Check back for new scripts!
- Scripts are run through the interactive menu in `liauh.sh`
- Each script auto-detects your OS and package manager
- Some scripts require `sudo` access (prompted once per session)
- See [DOCS.md](DOCS.md) for detailed usage examples and architecture

#!/bin/bash

# spoolman - Spoolman filament spool management (Donkie/Spoolman)
# Install, update, detect, back up and completely remove standalone, /opt and Docker installs
# Actions: install | update | detect | backup | uninstall
#
# Variables (from catalog.yaml prompts):
#   INSTALL_METHOD   standalone = native install + systemd, docker = compose stack
#   TARGET_USER      owner of the Spoolman install (default: SUDO_USER)
#   SPOOLMAN_PORT    web UI port (default: 7912)
#   SPOOLMAN_TZ      timezone for the Docker container (empty = detect)
#   PURGE            yes = also delete database, data, images, volumes
#   CLEAN_MOONRAKER  yes = comment out [spoolman] sections in moonraker.conf
#   DO_BACKUP        yes = tar/SQLite backup before removal or update

set -eo pipefail
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# ============================================================
# DEFAULTS
# ============================================================

SPOOLMAN_PORT="${SPOOLMAN_PORT:-7912}"
TARGET_USER="${TARGET_USER:-${SUDO_USER:-$USER}}"
INSTALL_METHOD="${INSTALL_METHOD:-standalone}"
SPOOLMAN_TZ="${SPOOLMAN_TZ:-}"
PURGE="${PURGE:-no}"
CLEAN_MOONRAKER="${CLEAN_MOONRAKER:-no}"
DO_BACKUP="${DO_BACKUP:-yes}"
TS="$(date +%Y%m%d-%H%M%S)"

SPOOLMAN_ZIP_URL="https://github.com/Donkie/Spoolman/releases/latest/download/spoolman.zip"
SPOOLMAN_IMAGE="ghcr.io/donkie/spoolman:latest"
SERVICE_NAME="Spoolman.service"

HOME_DIR=""
BACKUP_DIR=""
ERRORS=0
DISCOVERED=0

UNITS=(); UUNITS=(); DIRS=(); DATA=(); ENVS=()
CONTAINERS=(); IMAGES=(); VOLUMES=(); COMPOSE=(); MOONCONF=()

# ============================================================
# HELPERS
# ============================================================

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "Action '$ACTION' needs root - run: sudo bash $0 \"$ACTION\""
    fi
}

resolve_user() {
    HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    if [[ -z "$HOME_DIR" || ! -d "$HOME_DIR" ]]; then
        log_error "No home directory for user: $TARGET_USER"
    fi
    BACKUP_DIR="${BACKUP_DIR:-$HOME_DIR/spoolman-backup}"
}

# run a command as TARGET_USER, also works when running via sudo
run_as() {
    if [[ "$(id -un)" == "$TARGET_USER" ]]; then
        "$@"
    elif command_exists sudo; then
        sudo -u "$TARGET_USER" \
            env HOME="$HOME_DIR" USER="$TARGET_USER" LOGNAME="$TARGET_USER" "$@"
    else
        su -s /bin/bash - "$TARGET_USER" -c "$(printf '%q ' "$@")"
    fi
}

# systemctl --user for the target user, also works when running via sudo
uctl() {
    local uid
    uid="$(id -u "$TARGET_USER")"
    if [[ "$(id -un)" == "$TARGET_USER" ]]; then
        systemctl --user "$@"
    else
        sudo -u "$TARGET_USER" \
            env "XDG_RUNTIME_DIR=/run/user/${uid}" \
                "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${uid}/bus" \
            systemctl --user "$@"
    fi
}

# read a value from a Spoolman .env file, quotes and comments stripped
env_val() {
    local file="$1" key="$2" v
    v="$(awk -F= -v k="$key" '$1==k{sub(/^[^=]*=/,"");print;exit}' "$file" 2>/dev/null || true)"
    v="${v%%#*}"; v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    printf '%s' "${v//[[:space:]]/}"
}

# write a key into a Spoolman .env file (replaces commented-out keys too)
set_env_val() {
    local file="$1" key="$2" val="$3"
    [[ -f "$file" ]] || return 0
    if grep -qE "^[#[:space:]]*${key}=" "$file"; then
        sed -i -E "s|^[#[:space:]]*${key}=.*|${key}=${val}|" "$file"
    else
        printf '%s=%s\n' "$key" "$val" >> "$file"
    fi
}

# rm -rf with a blacklist for critical paths
safe_rm() {
    local path="$1"
    case "$path" in
        /|/home|/opt|/root|/usr|/var|"$HOME_DIR"|"$HOME_DIR/.local"|"$HOME_DIR/.local/share")
            log_error "Refusing to delete critical path: $path"
            ;;
    esac
    if ! rm -rf -- "$path"; then
        log_warn "Failed to delete: $path"
        ERRORS=$((ERRORS + 1))
    fi
}

# version from pyproject.toml of a standalone install
spoolman_version() {
    local dir="$1" v=""
    if [[ -f "$dir/pyproject.toml" ]]; then
        v="$(awk -F'"' '/^version[[:space:]]*=/{print $2; exit}' "$dir/pyproject.toml" 2>/dev/null || true)"
    fi
    printf '%s' "${v:-unknown}"
}

detect_timezone() {
    local tz=""
    if command_exists timedatectl; then
        tz="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
    fi
    if [[ -z "$tz" && -f /etc/timezone ]]; then
        tz="$(head -n1 /etc/timezone 2>/dev/null || true)"
    fi
    if [[ -z "$tz" && -L /etc/localtime ]]; then
        tz="$(readlink -f /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')"
    fi
    printf '%s' "${tz:-UTC}"
}

compose_cmd() {
    if command_exists docker && docker compose version &>/dev/null; then
        echo "docker compose"
    elif command_exists docker-compose; then
        echo "docker-compose"
    else
        echo ""
    fi
}

show_access() {
    local ip
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
    [[ -n "$ip" ]] || ip="<server-ip>"
    log_info "Spoolman UI: http://${ip}:${SPOOLMAN_PORT}"
}

# take the port from an existing install instead of the default
resolve_port() {
    local v="" c
    if [[ ${#ENVS[@]} -gt 0 ]]; then
        v="$(env_val "${ENVS[0]}" SPOOLMAN_PORT)"
    fi
    if [[ -z "$v" && ${#COMPOSE[@]} -gt 0 ]]; then
        c="$(grep -oE '[0-9]+:8000' "${COMPOSE[0]}" 2>/dev/null | head -n1 || true)"
        v="${c%%:*}"
    fi
    [[ -n "$v" ]] && SPOOLMAN_PORT="$v"
    return 0
}

# ============================================================
# DISCOVERY
# ============================================================

discover() {
    resolve_user
    DISCOVERED=1

    mapfile -t UNITS < <(find /etc/systemd/system /lib/systemd/system /usr/lib/systemd/system \
        -maxdepth 1 -iname 'spoolman*.service' 2>/dev/null | sort -u || true)
    mapfile -t UUNITS < <(find "$HOME_DIR/.config/systemd/user" \
        -maxdepth 1 -iname 'spoolman*.service' 2>/dev/null | sort -u || true)

    local d
    for d in "$HOME_DIR"/Spoolman "$HOME_DIR"/Spoolman-* "$HOME_DIR"/spoolman \
             /opt/spoolman /opt/Spoolman "$HOME_DIR"/printer_data/spoolman; do
        [[ -d "$d" ]] || continue
        if [[ -d "$d/.venv" || -f "$d/scripts/install.sh" || -f "$d/.env" || -f "$d/docker-compose.yml" ]]; then
            DIRS+=("$d")
            if [[ -f "$d/.env" ]]; then
                ENVS+=("$d/.env")
            fi
        fi
    done

    if [[ -d "$HOME_DIR/.local/share/spoolman" ]]; then
        DATA+=("$HOME_DIR/.local/share/spoolman")
    fi
    local e k v
    for e in "${ENVS[@]}"; do
        for k in SPOOLMAN_DIR_DATA SPOOLMAN_DIR_BACKUPS SPOOLMAN_DIR_LOGS; do
            v="$(env_val "$e" "$k")"
            if [[ -n "$v" && -d "$v" ]]; then
                DATA+=("$v")
            fi
        done
    done
    if [[ ${#DATA[@]} -gt 0 ]]; then
        mapfile -t DATA < <(printf '%s\n' "${DATA[@]}" | awk 'NF && !seen[$0]++')
    fi

    if command_exists docker && docker info &>/dev/null; then
        mapfile -t CONTAINERS < <(docker ps -a --format '{{.Names}}\t{{.Image}}' 2>/dev/null \
            | grep -Ei 'spoolman' | cut -f1 || true)
        mapfile -t IMAGES < <(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
            | grep -Ei 'spoolman' || true)
        mapfile -t VOLUMES < <(docker volume ls --format '{{.Name}}' 2>/dev/null \
            | grep -Ei 'spoolman' || true)
        mapfile -t COMPOSE < <(find "$HOME_DIR" /opt -maxdepth 3 \
            \( -name 'docker-compose.y*ml' -o -name 'compose.y*ml' \) 2>/dev/null \
            | xargs -r grep -lEi 'donkie/spoolman' 2>/dev/null | sort -u || true)
    fi

    mapfile -t MOONCONF < <(find "$HOME_DIR" -maxdepth 4 -name 'moonraker.conf' 2>/dev/null \
        | xargs -r grep -lE '^\[(spoolman|update_manager spoolman)\]' 2>/dev/null | sort -u || true)
}

found_count() {
    echo $(( ${#UNITS[@]} + ${#UUNITS[@]} + ${#DIRS[@]} + ${#DATA[@]} \
           + ${#CONTAINERS[@]} + ${#COMPOSE[@]} ))
}

show_findings() {
    local f
    log_section "Spoolman installation (user: $TARGET_USER)"
    printf "  %-20s %s\n" "system units:"     "${#UNITS[@]}"
    printf "  %-20s %s\n" "user units:"       "${#UUNITS[@]}"
    printf "  %-20s %s\n" "install dirs:"     "${#DIRS[@]}"
    printf "  %-20s %s\n" "data dirs:"        "${#DATA[@]}"
    printf "  %-20s %s\n" "docker container:" "${#CONTAINERS[@]}"
    printf "  %-20s %s\n" "docker images:"    "${#IMAGES[@]}"
    printf "  %-20s %s\n" "docker volumes:"   "${#VOLUMES[@]}"
    printf "  %-20s %s\n" "compose files:"    "${#COMPOSE[@]}"
    printf "  %-20s %s\n" "moonraker.conf:"   "${#MOONCONF[@]}"
    for f in "${UNITS[@]}" "${UUNITS[@]}" "${DIRS[@]}" "${DATA[@]}" \
             "${COMPOSE[@]}" "${MOONCONF[@]}"; do
        printf "    - %s\n" "$f"
    done
}

# ============================================================
# INSTALL
# ============================================================

install_deps() {
    detect_os
    log_section "Dependencies"
    $PKG_UPDATE || true

    case "$PKG_TYPE" in
        deb)
            $PKG_INSTALL curl unzip tar sqlite3 libpq-dev || log_error "Failed to install prerequisites"
            ;;
        rpm)
            $PKG_INSTALL curl unzip tar sqlite || log_warn "Some prerequisites could not be installed"
            $PKG_INSTALL libpq-devel || $PKG_INSTALL postgresql-devel \
                || log_warn "No PostgreSQL headers - install libpq-devel manually if the sync fails"
            ;;
        pacman)
            $PKG_INSTALL curl unzip tar sqlite postgresql-libs || log_error "Failed to install prerequisites"
            ;;
        zypper)
            $PKG_INSTALL curl unzip tar sqlite3 || log_warn "Some prerequisites could not be installed"
            $PKG_INSTALL postgresql-devel \
                || log_warn "No PostgreSQL headers - install postgresql-devel manually if the sync fails"
            ;;
        apk)
            $PKG_INSTALL curl unzip tar sqlite bash || log_error "Failed to install prerequisites"
            $PKG_INSTALL libpq-dev || $PKG_INSTALL postgresql-dev \
                || log_warn "No PostgreSQL headers - install libpq-dev manually if the sync fails"
            ;;
    esac
    log_info "Prerequisites ready"
}

# download the latest release zip and unpack it into $1
fetch_release() {
    local dest="$1" tmp
    tmp="$(mktemp -d)"

    log_info "Downloading latest Spoolman release..."
    curl -fsSL "$SPOOLMAN_ZIP_URL" -o "$tmp/spoolman.zip" || {
        rm -rf "$tmp"
        log_error "Download failed: $SPOOLMAN_ZIP_URL"
    }

    mkdir -p "$dest"
    unzip -q -o "$tmp/spoolman.zip" -d "$dest" || {
        rm -rf "$tmp"
        log_error "Failed to unpack the release archive"
    }
    rm -rf "$tmp"

    chown -R "$TARGET_USER":"$(id -gn "$TARGET_USER")" "$dest" 2>/dev/null || true
    log_info "Release unpacked: $dest"
}

# run the upstream installer (uv + venv + .env), systemd is handled by us
run_upstream_installer() {
    local dir="$1"
    log_section "Spoolman backend"
    log_info "Running upstream installer - this downloads uv and syncs Python dependencies..."
    run_as bash -c "cd '$dir' && bash ./scripts/install.sh -systemd=no" \
        || log_error "Upstream installer failed - see output above"
}

install_service() {
    local dir="$1"

    if ! command_exists systemctl; then
        log_warn "systemd not available - start Spoolman manually: bash $dir/scripts/start.sh"
        return 0
    fi

    log_section "Service"
    cat > "/etc/systemd/system/${SERVICE_NAME}" <<EOF
[Unit]
Description=Spoolman
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=bash ${dir}/scripts/start.sh
WorkingDirectory=${dir}
User=${TARGET_USER}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload || true
    systemctl enable "$SERVICE_NAME" &>/dev/null || log_warn "Failed to enable $SERVICE_NAME"
    systemctl restart "$SERVICE_NAME" || log_error "Failed to start $SERVICE_NAME"
    log_info "Service $SERVICE_NAME enabled and started"
}

install_standalone() {
    local dir="$HOME_DIR/Spoolman"

    log_section "Standalone install ($dir)"
    if [[ -e "$dir" ]]; then
        log_error "Directory already exists: $dir - use 'update' or 'uninstall' first"
    fi

    install_deps
    fetch_release "$dir"
    run_upstream_installer "$dir"

    set_env_val "$dir/.env" SPOOLMAN_HOST "0.0.0.0"
    set_env_val "$dir/.env" SPOOLMAN_PORT "$SPOOLMAN_PORT"
    chown "$TARGET_USER":"$(id -gn "$TARGET_USER")" "$dir/.env" 2>/dev/null || true

    install_service "$dir"
    log_info "Spoolman $(spoolman_version "$dir") installed for user $TARGET_USER"
}

install_docker_stack() {
    local dir="$HOME_DIR/spoolman" cc tz

    command_exists docker || log_error "Docker is not installed - install it first (ulh > Container & Virtualization > docker)"
    docker info &>/dev/null || log_error "Docker daemon not reachable"
    cc="$(compose_cmd)"
    [[ -n "$cc" ]] || log_error "Docker Compose not available - install it first (ulh > Container & Virtualization > docker-compose)"

    log_section "Docker install ($dir)"
    mkdir -p "$dir/data"
    chown "$TARGET_USER":"$(id -gn "$TARGET_USER")" "$dir" 2>/dev/null || true
    # the container runs as uid/gid 1000 (PUID/PGID defaults)
    chown -R 1000:1000 "$dir/data" 2>/dev/null || log_warn "Could not chown $dir/data to 1000:1000"

    tz="${SPOOLMAN_TZ:-$(detect_timezone)}"

    if [[ -f "$dir/docker-compose.yml" ]]; then
        cp -a -- "$dir/docker-compose.yml" "$dir/docker-compose.yml.bak-${TS}"
        log_warn "Existing compose file backed up: $dir/docker-compose.yml.bak-${TS}"
    fi

    cat > "$dir/docker-compose.yml" <<EOF
services:
  spoolman:
    image: ${SPOOLMAN_IMAGE}
    container_name: spoolman
    restart: unless-stopped
    volumes:
      - type: bind
        source: ./data
        target: /home/app/.local/share/spoolman
    ports:
      - "${SPOOLMAN_PORT}:8000"
    environment:
      - TZ=${tz}
EOF
    chown "$TARGET_USER":"$(id -gn "$TARGET_USER")" "$dir/docker-compose.yml" 2>/dev/null || true
    log_info "Compose file written (timezone: $tz)"

    $cc -f "$dir/docker-compose.yml" pull || log_warn "Image pull failed - using local image if present"
    $cc -f "$dir/docker-compose.yml" up -d || log_error "Failed to start the Spoolman container"
    log_info "Spoolman container started"
}

install_spoolman() {
    require_root
    discover

    if [[ "$(found_count)" -gt 0 ]]; then
        show_findings
        log_error "Spoolman is already installed - use 'update' or 'uninstall' first"
    fi

    case "${INSTALL_METHOD,,}" in
        docker)
            install_docker_stack
            ;;
        standalone|native|"")
            install_standalone
            ;;
        *)
            log_error "Unknown INSTALL_METHOD: $INSTALL_METHOD (use standalone or docker)"
            ;;
    esac

    show_access
}

# ============================================================
# UPDATE
# ============================================================

# start|stop|restart all discovered units without removing them
service_ctl() {
    local action="$1" u n
    for u in "${UUNITS[@]}"; do
        n="$(basename "$u")"
        uctl "$action" "$n" &>/dev/null || true
    done
    for u in "${UNITS[@]}"; do
        n="$(basename "$u")"
        systemctl "$action" "$n" &>/dev/null || true
    done
}

update_docker_stack() {
    local cc c
    cc="$(compose_cmd)"
    if [[ -z "$cc" ]]; then
        log_warn "Docker Compose not available - skipping container update"
        return 0
    fi

    log_section "Docker update"
    for c in "${COMPOSE[@]}"; do
        log_info "Updating stack: $c"
        $cc -f "$c" pull || log_warn "Image pull failed: $c"
        $cc -f "$c" up -d || log_warn "Restart failed: $c"
    done

    if [[ ${#COMPOSE[@]} -eq 0 && ${#CONTAINERS[@]} -gt 0 ]]; then
        log_warn "Container without compose file: ${CONTAINERS[*]} - update it manually"
    fi
}

update_standalone() {
    local dir="$1" old="${1}_old-${TS}" staging="${1}_new-${TS}"

    log_section "Standalone update ($dir)"
    log_info "Installed version: $(spoolman_version "$dir")"

    if [[ "$DO_BACKUP" == "yes" ]]; then
        backup_spoolman
    else
        log_warn "Backup skipped (DO_BACKUP=$DO_BACKUP)"
    fi

    # download first - a failed download leaves the running install untouched
    fetch_release "$staging"

    service_ctl stop
    mv -- "$dir" "$old" || log_error "Cannot move $dir aside"
    mv -- "$staging" "$dir" || {
        mv -- "$old" "$dir"
        log_error "Cannot activate the new version - old version restored"
    }

    if [[ -f "$old/.env" ]]; then
        cp -a -- "$old/.env" "$dir/.env"
        log_info "Kept existing .env"
    fi

    run_upstream_installer "$dir"
    chown -R "$TARGET_USER":"$(id -gn "$TARGET_USER")" "$dir" 2>/dev/null || true

    if [[ ${#UNITS[@]} -eq 0 && ${#UUNITS[@]} -eq 0 ]]; then
        log_warn "No service unit found - start Spoolman manually: bash $dir/scripts/start.sh"
    else
        service_ctl start
        log_info "Service restarted"
    fi

    if [[ "$DO_BACKUP" == "yes" ]]; then
        safe_rm "$old"
    else
        log_warn "Previous version kept: $old"
    fi

    log_info "Spoolman updated to $(spoolman_version "$dir")"
}

update_spoolman() {
    require_root
    discover
    show_findings

    if [[ "$(found_count)" -eq 0 ]]; then
        log_error "No Spoolman installation found - run 'install' first"
    fi

    local d handled=0
    if [[ ${#COMPOSE[@]} -gt 0 || ${#CONTAINERS[@]} -gt 0 ]]; then
        update_docker_stack
        handled=1
    fi

    for d in "${DIRS[@]}"; do
        [[ -f "$d/pyproject.toml" ]] || continue
        update_standalone "$d"
        handled=1
    done

    if [[ "$handled" -eq 0 ]]; then
        log_error "Nothing updatable found (no compose file, no standalone install directory)"
    fi

    resolve_port
    show_access
}

# ============================================================
# DETECT / BACKUP
# ============================================================

detect_spoolman() {
    discover
    show_findings
    if [[ "$(found_count)" -eq 0 ]]; then
        log_info "No Spoolman installation found"
    else
        log_info "Detection complete - nothing was changed"
    fi
}

backup_spoolman() {
    if [[ "$DISCOVERED" -eq 0 ]]; then
        discover
    fi

    local src=() c db
    src+=("${DATA[@]}" "${ENVS[@]}" "${UNITS[@]}" "${UUNITS[@]}" "${COMPOSE[@]}" "${MOONCONF[@]}")
    for c in "${COMPOSE[@]}"; do
        if [[ -d "$(dirname "$c")/data" ]]; then
            src+=("$(dirname "$c")/data")
        fi
    done

    if [[ ${#src[@]} -eq 0 ]]; then
        log_warn "Nothing to back up"
        return 0
    fi

    log_section "Backup"
    mkdir -p "$BACKUP_DIR" || log_error "Cannot create backup directory: $BACKUP_DIR"

    # consistent SQLite copy while the service may still be running
    if command_exists sqlite3 && [[ ${#DATA[@]} -gt 0 ]]; then
        while read -r db; do
            [[ -n "$db" ]] || continue
            if sqlite3 "$db" ".backup '${BACKUP_DIR}/spoolman-${TS}.db'"; then
                log_info "SQLite dump: ${BACKUP_DIR}/spoolman-${TS}.db"
            else
                log_warn "SQLite dump failed: $db"
            fi
        done < <(find "${DATA[@]}" -maxdepth 2 -name 'spoolman.db' 2>/dev/null || true)
    fi

    tar --ignore-failed-read -czf "${BACKUP_DIR}/spoolman-${TS}.tgz" -- "${src[@]}" \
        || log_error "Backup failed"
    chown -R "$TARGET_USER":"$(id -gn "$TARGET_USER")" "$BACKUP_DIR" 2>/dev/null || true
    log_info "Backup: ${BACKUP_DIR}/spoolman-${TS}.tgz"
}

# ============================================================
# UNINSTALL
# ============================================================

remove_services() {
    if [[ ${#UNITS[@]} -eq 0 && ${#UUNITS[@]} -eq 0 ]]; then
        return 0
    fi
    log_section "Services"

    local u n
    for u in "${UUNITS[@]}"; do
        n="$(basename "$u")"
        log_info "Removing user unit: $n"
        uctl stop "$n" 2>/dev/null || true
        uctl disable "$n" 2>/dev/null || true
        rm -f -- "$u" || log_warn "Failed to delete: $u"
    done
    if [[ ${#UUNITS[@]} -gt 0 ]]; then
        uctl daemon-reload 2>/dev/null || true
        uctl reset-failed 2>/dev/null || true
    fi

    for u in "${UNITS[@]}"; do
        n="$(basename "$u")"
        log_info "Removing system unit: $n"
        systemctl stop "$n" 2>/dev/null || true
        systemctl disable "$n" 2>/dev/null || true
        rm -f -- "$u" || log_warn "Failed to delete: $u"
    done
    if [[ ${#UNITS[@]} -gt 0 ]]; then
        systemctl daemon-reload || true
        systemctl reset-failed || true
    fi

    if pgrep -f 'spoolman.main:app' &>/dev/null; then
        log_warn "Killing leftover uvicorn worker(s)"
        pkill -f 'spoolman.main:app' || true
    fi
    return 0
}

remove_docker() {
    if [[ ${#CONTAINERS[@]} -eq 0 && ${#COMPOSE[@]} -eq 0 ]]; then
        return 0
    fi
    log_section "Docker"

    local cc c i v
    cc="$(compose_cmd)"
    for c in "${COMPOSE[@]}"; do
        log_info "compose down: $c"
        if [[ -z "$cc" ]]; then
            log_warn "Docker Compose not available: $c"
        elif [[ "$PURGE" == "yes" ]]; then
            $cc -f "$c" down -v --remove-orphans || log_warn "compose down failed: $c"
        else
            $cc -f "$c" down --remove-orphans || log_warn "compose down failed: $c"
        fi
    done
    for c in "${CONTAINERS[@]}"; do
        log_info "Removing container: $c"
        docker rm -f -- "$c" &>/dev/null || log_warn "Failed to remove container: $c"
    done

    if [[ "$PURGE" == "yes" ]]; then
        for i in "${IMAGES[@]}"; do
            docker rmi -f -- "$i" &>/dev/null || log_warn "Failed to remove image: $i"
        done
        for v in "${VOLUMES[@]}"; do
            docker volume rm -f -- "$v" &>/dev/null || log_warn "Failed to remove volume: $v"
        done
    else
        log_info "Docker images and volumes kept (PURGE=no)"
    fi
    return 0
}

remove_files() {
    log_section "Files"
    local d
    for d in "${DIRS[@]}"; do
        # docker layout: ./data next to the compose file holds the database
        if [[ "$PURGE" != "yes" && -d "$d/data" ]]; then
            log_info "Removing: $d (keeping $d/data)"
            find "$d" -mindepth 1 -maxdepth 1 ! -name data -exec rm -rf -- {} + \
                || { log_warn "Failed to clean: $d"; ERRORS=$((ERRORS + 1)); }
            log_warn "Database kept: $d/data"
        else
            log_info "Removing: $d"
            safe_rm "$d"
        fi
    done

    if [[ "$PURGE" == "yes" ]]; then
        for d in "${DATA[@]}"; do
            log_warn "Deleting data: $d"
            safe_rm "$d"
        done
    elif [[ ${#DATA[@]} -gt 0 ]]; then
        log_info "Database kept: ${DATA[*]}"
    fi
}

clean_moonraker() {
    if [[ ${#MOONCONF[@]} -eq 0 ]]; then
        return 0
    fi

    local m tmp
    if [[ "$CLEAN_MOONRAKER" != "yes" ]]; then
        for m in "${MOONCONF[@]}"; do
            log_warn "Still references spoolman: $m"
        done
        return 0
    fi

    log_section "Moonraker"
    for m in "${MOONCONF[@]}"; do
        cp -a -- "$m" "${m}.bak-${TS}" || log_error "Cannot back up: $m"
        tmp="$(mktemp)"
        awk '
            /^[[:space:]]*\[/ { sec = ($0 ~ /^[[:space:]]*\[(spoolman|update_manager[[:space:]]+spoolman)\][[:space:]]*$/) ? 1 : 0 }
            { print (sec ? "#" $0 : $0) }
        ' "$m" > "$tmp" && cat -- "$tmp" > "$m"
        rm -f -- "$tmp"
        log_info "Patched: $m (backup: ${m}.bak-${TS})"
    done
    log_warn "Restart moonraker to apply: systemctl restart moonraker"
}

uninstall_spoolman() {
    discover
    show_findings

    if [[ "$(found_count)" -eq 0 ]]; then
        log_info "No Spoolman installation found - nothing to do"
        return 0
    fi

    if [[ "$PURGE" == "yes" ]]; then
        log_warn "PURGE=yes - database and data directories will be deleted"
    fi
    if [[ "$DO_BACKUP" == "yes" ]]; then
        backup_spoolman
    else
        log_warn "Backup skipped (DO_BACKUP=$DO_BACKUP)"
    fi

    remove_services
    remove_docker
    remove_files
    clean_moonraker

    log_section "Result"
    if command_exists ss && ss -ltn "sport = :${SPOOLMAN_PORT}" 2>/dev/null | grep -q ":${SPOOLMAN_PORT}"; then
        log_warn "Port ${SPOOLMAN_PORT} is still in use"
    fi
    if systemctl list-units --all 2>/dev/null | grep -qi 'spoolman'; then
        log_warn "systemd still knows a spoolman unit"
    fi

    if [[ "$ERRORS" -gt 0 ]]; then
        log_error "Finished with $ERRORS failed step(s)"
    fi

    if [[ "$PURGE" == "yes" ]]; then
        log_info "Spoolman completely uninstalled (data deleted)!"
    else
        log_info "Spoolman uninstalled (data preserved)!"
    fi
}

# ============================================================
# MAIN
# ============================================================

case "$ACTION" in
    install)
        install_spoolman
        ;;
    update)
        update_spoolman
        ;;
    detect)
        detect_spoolman
        ;;
    backup)
        discover
        backup_spoolman
        ;;
    uninstall)
        uninstall_spoolman
        ;;
    *)
        print_usage spoolman && exit 1
        ;;
esac

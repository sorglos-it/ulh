#!/bin/bash
# ulh - Self-update: ulh is a git clone and updates itself with git pull.
#
# Pulls only fast-forward and ignore file mode changes, so a local chmod
# never blocks an update.

# Number of commits the clone is behind origin (0 if unknown)
update_behind() {
    local n
    n=$(git -C "$ULH_ROOT" rev-list --count HEAD..origin/main 2>/dev/null) ||
        n=$(git -C "$ULH_ROOT" rev-list --count HEAD..origin/master 2>/dev/null) ||
        n=0
    echo "${n:-0}"
}

update_pull() {
    git -C "$ULH_ROOT" -c core.fileMode=false pull --ff-only origin main ||
        git -C "$ULH_ROOT" -c core.fileMode=false pull --ff-only origin master
}

update_is_clone() {
    [[ -d "$ULH_ROOT/.git" ]] && return 0
    msg_warn "Not a git repository"
    return 1
}

# --check-update
update_check() {
    update_is_clone || return 1
    git -C "$ULH_ROOT" fetch origin &>/dev/null
    local behind; behind=$(update_behind)
    if (( behind > 0 )); then
        msg_info "Updates available! Run: bash apps/cli/ulh.sh --update"
    else
        msg_ok "You are up to date."
    fi
    return 0
}

# --update
update_apply() {
    update_is_clone || return 1
    msg_info "Pulling latest version..."
    if update_pull 2>/dev/null; then
        msg_ok "Update successful!"
        return 0
    fi
    msg_err "Update failed. Check git status."
    return 1
}

# On every start: pull if behind, then restart the updated ulh
update_auto() {
    [[ -d "$ULH_ROOT/.git" ]] || return 0
    [[ -z "${ULH_UPDATED:-}" ]] || return 0     # restarted right after an update

    git -C "$ULH_ROOT" fetch origin &>/dev/null || return 0
    local behind; behind=$(update_behind)
    (( behind > 0 )) || return 0

    msg_info "Updating ulh ($behind commit(s) behind)..."
    if update_pull &>/dev/null; then
        msg_ok "ulh updated successfully - restarting..."
        echo ""
        export ULH_UPDATED=1
        exec bash "${ulh_DIR}/ulh.sh" "${ULH_ARGS[@]}"
    fi
    msg_warn "Auto-update failed - proceeding anyway"
    return 1
}

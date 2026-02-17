#!/bin/bash
# LIAUH - Menu Display & Navigation

# Global context tracking
CONTEXT_FROM="none"  # "none" or "repo"

# Get correct yq binary for current architecture
_get_yq() {
    if [[ -z "$_YQ_CACHE" ]]; then
        local arch=$(uname -m)
        case "$arch" in
            x86_64) _YQ_CACHE="${LIAUH_DIR}/lib/yq/yq-amd64" ;;
            aarch64) _YQ_CACHE="${LIAUH_DIR}/lib/yq/yq-arm64" ;;
            armv7l) _YQ_CACHE="${LIAUH_DIR}/lib/yq/yq-arm" ;;
            i686) _YQ_CACHE="${LIAUH_DIR}/lib/yq/yq-386" ;;
            *) _YQ_CACHE="yq" ;;  # Fallback to PATH
        esac
        [[ -x "$_YQ_CACHE" ]] || chmod +x "$_YQ_CACHE" 2>/dev/null
    fi
    echo "$_YQ_CACHE"
}

# Helper: execute yq with proper binary
_yq_eval() {
    local yq=$(_get_yq)
    "$yq" eval "$@"
}

menu_clear() { clear; printf '\033[H\033[2J\033[3J'; }

menu_header() {
    local title="$1"
    local version="${2:-}"
    
    echo "+==============================================================================+"
    
    if [[ -n "$version" ]]; then
        # With version: | title[padding] VERSION: version |
        # Box width: 80 = | (1) + space (1) + title + padding + space (1) + VERSION: ... + space (1) + | (1)
        local version_str="VERSION: ${version}"
        local padding=$(( 80 - 1 - 1 - ${#title} - 1 - ${#version_str} - 1 - 1 ))
        printf "| %s%*s %s |\n" "$title" $padding "" "$version_str"
    else
        # Without version: |  title |
        printf "| %s%*s|\n" "$title" $(( 77 - ${#title} )) ""
    fi
    
    echo "+==============================================================================+"
    echo "|"
}

menu_footer() {
    local show_back=$1
    local system_info="${OS_DISTRO} (${OS_FAMILY}) · v${OS_VERSION}"
    
    echo "|"
    echo "+==============================================================================+"
    
    if [[ $show_back -eq 1 ]]; then
        # Back button: |  b) Back (10 chars) + padding + | = 80
        printf "|  b) Back%*s|\n" 69 ""
    fi
    
    # Calculate padding for quit + system info
    # Total width: 80 = | (1) + 2 spaces (2) + "q) Quit" (7) + padding + system_info + space (1) + | (1)
    local len=$(( ${#system_info} + 12 ))
    local padding=$(( 80 - len ))
    echo  "$len -- $padding --$system_info--";
    printf "|  q) Quit%*s %s |\n" $padding "" "$system_info"
    
    echo "+==============================================================================+"
}

menu_error() { echo ""; echo "  ❌ $1"; echo ""; read -rp "  Press Enter..."; }
menu_confirm() { local r; read -rp "  $1 (y/N): " r; [[ "${r,,}" == "y" ]]; }
menu_valid_num() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= $2 )); }

# Prompt helpers
menu_prompt_input() {
    local a; echo -n "  $1 [${2:-}]: "; read -r a
    [[ -z "$a" ]] && a="${2:-}"; echo "$a"
}

menu_prompt_yesno() {
    local a; while true; do
        echo -n "  $1 [${2:-y}]: "; read -r a
        [[ -z "$a" ]] && a="${2:-y}"
        [[ "$a" =~ ^[yYnN] ]] && break; echo "  Please answer y/n"
    done
    [[ "$a" =~ ^[yY] ]] && echo "yes" || echo "no"
}

separator() { echo "──────────────────────────────────────────────────────────────────────────────"; }

# ============================================================================
# Helper Functions
# ============================================================================

_get_categories() {
    local -n ref=$1; ref=()
    while IFS= read -r c; do [[ -n "$c" ]] && ref+=("$c"); done <<< "$(yaml_categories | sort)"
}

_get_scripts() {
    local -n ref=$1; ref=(); local src="$2"
    while IFS= read -r s; do
        [[ -n "$s" ]] && yaml_os_compatible "$s" "$OS_DISTRO" "$OS_FAMILY" && [[ -f "$(yaml_script_path "$s")" ]] && ref+=("$s")
    done <<< "$src"
}

_has_custom_scripts() {
    [[ -f "${LIAUH_DIR}/custom.yaml" ]] || return 1
    yaml_load "custom"
    local found=0
    while IFS= read -r s; do
        [[ -n "$s" ]] && yaml_os_compatible "$s" "$OS_DISTRO" "$OS_FAMILY" && [[ -f "$(yaml_script_path "$s")" ]] && found=1 && break
    done <<< "$(yaml_scripts)"
    yaml_load "config"
    (( found == 1 ))
}

# ============================================================================
# Menu Display Functions
# ============================================================================

menu_show_repositories() {
    menu_clear
    menu_header "LIAUH - Linux Install and Update Helper" "${LIAUH_VERSION}"
    
    local i=1
    # Always show LIAUH system scripts
    printf "|  %d) LIAUH - Linux Install and Update Helper\n" $i
    ((i++))
    
    # Show enabled custom repositories
    local repo_names
    repo_names=$(repo_list_enabled "${LIAUH_DIR}")
    while IFS= read -r repo_name; do
        [[ -z "$repo_name" ]] && continue
        local repo_display_name=$(repo_get_name "${LIAUH_DIR}/custom/repo.yaml" "$repo_name")
        printf "|  %d) %s\n" $i "$repo_display_name"
        ((i++))
    done <<< "$repo_names"
    
    menu_footer 0
}

# Show LIAUH system scripts (categories)
menu_show_main() {
    menu_clear
    menu_header "LIAUH - Linux Install and Update Helper"
    local -a cats; _get_categories cats
    local i=1; for c in "${cats[@]}"; do printf "|  %d) %s\n" $i "$c"; ((i++)); done
    
    # Show back button only if coming from repo menu
    if [[ "$CONTEXT_FROM" == "repo" ]]; then
        menu_footer 1
    else
        menu_footer 0
    fi
}

menu_show_category() {
    menu_clear
    menu_header "Category: $1"
    local -a scripts; _get_scripts scripts "$(yaml_scripts_by_cat "$1")"
    if (( ${#scripts[@]} == 0 )); then 
        echo "|  No scripts available."
    else 
        local i=1; for s in "${scripts[@]}"; do 
            printf "|  %d) %s - %s\n" $i "$s" "$(yaml_info "$s" description)"
            ((i++))
        done
    fi
    menu_footer 1
}

menu_show_actions() {
    menu_clear
    menu_header "$1 - $(yaml_info "$1" description)"
    local count=$(yaml_action_count "$1"); [[ -z "$count" || "$count" == "null" ]] && count=0
    if (( count == 0 )); then 
        echo "|  No actions."
    else 
        for ((i=0; i<count; i++)); do
            local n=$(yaml_action_name "$1" $i) d=$(yaml_action_description "$1" $i)
            [[ -n "$d" && "$d" != "null" ]] && printf "|  %d) %s - %s\n" $((i+1)) "$n" "$d" || printf "|  %d) %s\n" $((i+1)) "$n"
        done
    fi
    menu_footer 1
}

# Show custom repo scripts
menu_show_custom_repo() {
    local repo_name="$1"
    local repo_path="$2"
    local repo_display_name=$(repo_get_name "${LIAUH_DIR}/custom/repo.yaml" "$repo_name")
    
    menu_clear
    menu_header "Custom: $repo_display_name"
    
    # Load custom.yaml from repo
    if [[ ! -f "$repo_path/custom.yaml" ]]; then
        echo "|  No custom.yaml found in $repo_path"
        menu_footer 1
        return 1
    fi
    
    # Get scripts from this repo's custom.yaml
    local -a scripts=()
    while IFS= read -r script_name; do
        [[ -n "$script_name" ]] && scripts+=("$script_name")
    done <<< "$(_yq_eval ".scripts | keys | .[]" "$repo_path/custom.yaml" 2>/dev/null)"
    
    if (( ${#scripts[@]} == 0 )); then
        echo "|  No scripts available in this repository."
    else
        local i=1; for s in "${scripts[@]}"; do 
            local desc=$(_yq_eval ".scripts.$s.description" "$repo_path/custom.yaml" 2>/dev/null)
            printf "|  %d) %s - %s\n" $i "$s" "$desc"
            ((i++))
        done
    fi
    
    menu_footer 1
}

menu_show_custom_repo_actions() {
    local repo_name="$1"
    local repo_path="$2"
    local script_name="$3"
    local repo_display_name=$(repo_get_name "${LIAUH_DIR}/custom/repo.yaml" "$repo_name")
    
    menu_clear
    menu_header "Custom: $repo_display_name - $script_name"
    
    # Get actions from repo's custom.yaml
    local count
    count=$(_yq_eval ".scripts.$script_name.actions | length" "$repo_path/custom.yaml" 2>/dev/null)
    [[ -z "$count" || "$count" == "null" ]] && count=0
    
    if (( count == 0 )); then 
        echo "  No actions."
    else 
        for ((i=0; i<count; i++)); do
            local n=$(_yq_eval ".scripts.$script_name.actions[$i].name" "$repo_path/custom.yaml" 2>/dev/null)
            local d=$(_yq_eval ".scripts.$script_name.actions[$i].description" "$repo_path/custom.yaml" 2>/dev/null)
            [[ -n "$d" && "$d" != "null" ]] && printf "|  %d) %s - %s\n" $((i+1)) "$n" "$d" || printf "|  %d) %s\n" $((i+1)) "$n"
        done
    fi
    menu_footer 1
}

# ============================================================================
# Navigation Loops
# ============================================================================

menu_main() {
    # Check if there are custom repositories
    local custom_repos
    custom_repos=$(repo_list_enabled "${LIAUH_DIR}")
    
    if [[ -n "$custom_repos" ]]; then
        # Show repository selector
        menu_repositories
    else
        # Show LIAUH scripts directly (no repos)
        menu_liauh_scripts
    fi
}

menu_repositories() {
    while true; do
        menu_show_repositories
        
        # Count menu items: LIAUH + custom repos
        local i=1
        local -a choices=("liauh")  # First choice is LIAUH
        ((i++))
        
        while IFS= read -r repo_name; do
            [[ -z "$repo_name" ]] && continue
            choices+=("$repo_name")
            ((i++))
        done <<< "$(repo_list_enabled "${LIAUH_DIR}")"
        
        local max=$((i-1))
        
        echo ""; local input; read -rp "  Choose: " input || exit 0
        case "$input" in
            q|Q) echo "  Goodbye!"; exit 0 ;;
            [0-9]*)
                if menu_valid_num "$input" $max; then
                    local choice="${choices[$((input-1))]}"
                    if [[ "$choice" == "liauh" ]]; then
                        CONTEXT_FROM="repo"
                        menu_liauh_scripts
                    else
                        local repo_path=$(repo_get_path "${LIAUH_DIR}/custom/repo.yaml" "$choice")
                        menu_custom_repo_scripts "$choice" "$repo_path"
                    fi
                else menu_error "Invalid (1-$max)" ; fi ;;
            "") ;; *) menu_error "Invalid input" ;;
        esac
    done
}

menu_liauh_scripts() {
    while true; do
        menu_show_main
        local -a cats; _get_categories cats; local max=${#cats[@]}
        echo ""; local input; read -rp "  Choose: " input || return
        case "$input" in
            q|Q) exit 0 ;;
            b|B) CONTEXT_FROM="none"; return ;;
            [0-9]*) menu_valid_num "$input" $max && menu_category "${cats[$((input-1))]}" || menu_error "Invalid (1-$max)" ;;
            "") ;; *) menu_error "Invalid input" ;;
        esac
    done
}

menu_category() {
    while true; do
        menu_show_category "$1"
        local -a scripts; _get_scripts scripts "$(yaml_scripts_by_cat "$1")"; local max=${#scripts[@]}
        echo ""; local input; read -rp "  Choose: " input || return
        case "$input" in
            q|Q) exit 0 ;; b|B) return ;;
            [0-9]*) menu_valid_num "$input" $max && menu_actions "${scripts[$((input-1))]}" || menu_error "Invalid (1-$max)" ;;
            "") ;; *) menu_error "Invalid input" ;;
        esac
    done
}

menu_actions() {
    while true; do
        menu_show_actions "$1"
        local count=$(yaml_action_count "$1"); [[ -z "$count" || "$count" == "null" ]] && count=0
        echo ""; local input; read -rp "  Choose: " input || return
        case "$input" in
            q|Q) exit 0 ;; b|B) return ;;
            [0-9]*)
                if (( count > 0 )) && menu_valid_num "$input" $count; then
                    local idx=$((input-1))
                    execute_action "$1" $idx
                else menu_error "Invalid (1-$count)"; fi ;;
            "") ;; *) menu_error "Invalid input" ;;
        esac
    done
}

menu_custom_repo_scripts() {
    local repo_name="$1"
    local repo_path="$2"
    
    while true; do
        menu_show_custom_repo "$repo_name" "$repo_path" || return
        
        # Get scripts from repo's custom.yaml
        local -a scripts=()
        while IFS= read -r script_name; do
            [[ -n "$script_name" ]] && scripts+=("$script_name")
        done <<< "$(_yq_eval ".scripts | keys | .[]" "$repo_path/custom.yaml" 2>/dev/null)"
        
        local max=${#scripts[@]}
        echo ""; local input; read -rp "  Choose: " input || return
        case "$input" in
            q|Q) exit 0 ;;
            b|B) return ;;
            [0-9]*)
                if menu_valid_num "$input" $max; then
                    menu_custom_repo_actions "$repo_name" "$repo_path" "${scripts[$((input-1))]}"
                else menu_error "Invalid (1-$max)"; fi ;;
            "") ;; *) menu_error "Invalid input" ;;
        esac
    done
}

menu_custom_repo_actions() {
    local repo_name="$1"
    local repo_path="$2"
    local script_name="$3"
    
    while true; do
        menu_show_custom_repo_actions "$repo_name" "$repo_path" "$script_name"
        
        # Get actions from repo's custom.yaml
        local count
        count=$(_yq_eval ".scripts.$script_name.actions | length" "$repo_path/custom.yaml" 2>/dev/null)
        [[ -z "$count" || "$count" == "null" ]] && count=0
        
        echo ""; local input; read -rp "  Choose: " input || return
        case "$input" in
            q|Q) exit 0 ;;
            b|B) return ;;
            [0-9]*)
                if (( count > 0 )) && menu_valid_num "$input" $count; then
                    execute_custom_repo_action "$repo_name" "$repo_path" "$script_name" $((input-1))
                else menu_error "Invalid (1-$count)"; fi ;;
            "") ;; *) menu_error "Invalid input" ;;
        esac
    done
}

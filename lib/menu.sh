#!/bin/bash
# LIAUH - Menu Display & Navigation

menu_clear() { clear; printf '\033[H\033[2J\033[3J'; }

menu_header() {
    local title="$1" w=76 tlen=${#1} pad=$(( (76 - ${#1} - 2) / 2 ))
    echo "+$(printf "%${w}s" | tr ' ' '=')+"
    printf "|%*s%s%*s|\n" $pad "" "$title" $((w - pad - tlen)) ""
    echo "+$(printf "%${w}s" | tr ' ' '=')+"
    echo ""
}

menu_error() { echo ""; echo "  ❌ $1"; echo ""; read -rp "  Press Enter..."; }
menu_confirm() { local r; read -rp "  $1 (y/N): " r; [[ "${r,,}" == "y" ]]; }
menu_valid_num() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= $2 )); }

# Prompt helpers for action configuration
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

# ============================================================================
# Menu Screens
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

menu_show_main() {
    menu_clear; menu_header "LIAUH - Linux Install and Update Helper"
    echo "  Version: ${VERSION} | Detected: ${OS_DISTRO} (${OS_FAMILY}) - ${OS_VERSION}"; echo ""
    local -a cats; _get_categories cats
    local i=1; for c in "${cats[@]}"; do printf "  %2d) %s\n" $i "$c"; ((i++)); done
    if _has_custom_scripts; then echo ""; echo "   c) Custom scripts"; fi
    echo ""
    separator; echo "   q) Quit"; separator
}

menu_show_category() {
    menu_clear; menu_header "Category: $1"
    local -a scripts; _get_scripts scripts "$(yaml_scripts_by_cat "$1")"
    if (( ${#scripts[@]} == 0 )); then echo "  No scripts available."
    else local i=1; for s in "${scripts[@]}"; do printf "  %2d) %-20s - %s\n" $i "$s" "$(yaml_info "$s" description)"; ((i++)); done; fi
    echo ""; separator; echo "  b) Back"; echo "  q) Quit"; separator
}

menu_show_actions() {
    menu_clear; menu_header "$1 - $(yaml_info "$1" description)"
    local count=$(yaml_action_count "$1"); [[ -z "$count" || "$count" == "null" ]] && count=0
    if (( count == 0 )); then echo "  No actions."
    else for ((i=0; i<count; i++)); do
        local n=$(yaml_action_name "$1" $i) d=$(yaml_action_description "$1" $i)
        [[ -n "$d" && "$d" != "null" ]] && printf "  %2d) %-15s - %s\n" $((i+1)) "$n" "$d" || printf "  %2d) %s\n" $((i+1)) "$n"
    done; fi
    echo ""; separator; echo "  b) Back"; echo "  q) Quit"; separator
}

menu_show_custom() {
    menu_clear; menu_header "Custom Scripts"
    yaml_load "custom"
    local -a scripts; _get_scripts scripts "$(yaml_scripts)"
    if (( ${#scripts[@]} == 0 )); then echo "  No custom scripts."
    else local i=1; for s in "${scripts[@]}"; do printf "  %2d) %-20s - %s\n" $i "$s" "$(yaml_info "$s" description)"; ((i++)); done; fi
    yaml_load "config"
    echo ""; separator; echo "  b) Back"; echo "  q) Quit"; separator
}

# ============================================================================
# Navigation Loops
# ============================================================================

menu_main() {
    while true; do
        menu_show_main
        local -a cats; _get_categories cats; local max=${#cats[@]}
        echo ""; local input; read -rp "  Choose: " input || exit 0
        case "$input" in
            q|Q) echo "  Goodbye!"; exit 0 ;;
            c|C) _has_custom_scripts && menu_custom || menu_error "No custom scripts available" ;;
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

menu_custom() {
    while true; do
        menu_show_custom
        yaml_load "custom"
        local -a scripts; _get_scripts scripts "$(yaml_scripts)"; local max=${#scripts[@]}
        yaml_load "config"
        echo ""; local input; read -rp "  Choose: " input || return
        case "$input" in
            q|Q) exit 0 ;; b|B) return ;;
            [0-9]*)
                if (( max > 0 )) && menu_valid_num "$input" $max; then
                    yaml_load "custom"; menu_actions "${scripts[$((input-1))]}"; yaml_load "config"
                else menu_error "Invalid"; fi ;;
            "") ;; *) menu_error "Invalid input" ;;
        esac
    done
}

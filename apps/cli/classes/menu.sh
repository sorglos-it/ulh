#!/bin/bash
# ulh - Menu Display & Navigation

# Load colors from centralized library
source "${BASH_SOURCE%/*}/colors.sh"

# Global context tracking
CONTEXT_FROM="none"  # "none" or "repo"

# yq: get_yq / yq_eval come from yaml.sh

menu_clear() { clear; printf '\033[H\033[2J\033[3J'; }

menu_header() {
    local title="$1"
    local version="${2:-}"
    
    separator_dots
    
    if [[ -n "$version" ]]; then
        # With version: | title[padding] VERSION: version |
        # Box width: 80 = | (1) + space (1) + title + padding + space (1) + VERSION: ... + space (1) + | (1)
        local version_str; version_str="$(t menu.version "$version")"
        local padding=$(( 80 - 1 - 1 - ${#title} - 1 - ${#version_str} - 1 - 1 ))
        printf "| %s%*s %s |\n" "$title" $padding "" "$version_str"
    else
        # Without version: |  title |
        printf "| %s%*s|\n" "$title" $(( 77 - ${#title} )) ""
    fi
    
    separator_dots
    echo "|"
}

# One line of the frame: |  text<padding>|  (80 wide; longer text is not cut)
menu_line() {
    local text="$1" pad=$(( 76 - ${#1} ))
    (( pad < 0 )) && pad=0
    printf "|  %s%*s|\n" "$text" $pad ""
}

# Pad text to a width in characters into the variable named by $1.
# printf "%-20s" counts bytes: "Überwachung" would come out one short.
menu_pad() {
    local n=$(( $3 - ${#2} ))
    (( n < 0 )) && n=0
    printf -v "$1" '%s%*s' "$2" "$n" ""
}

menu_footer() {
    local show_back=$1
    local show_search=${2:-0}
    local system_info="${OS_DISTRO} (${OS_FAMILY}) · v${OS_VERSION}"

    echo "|"
    separator_dots

    (( show_search == 1 )) && menu_line "$(t menu.key_search)"
    (( show_back == 1 )) && menu_line "$(t menu.key_back)"
    menu_line "$(t menu.key_lang "$(t lang.name)")"

    # Quit on the left, system info on the right
    local quit; quit="$(t menu.key_quit)"
    local padding=$(( 80 - 3 - ${#quit} - 1 - ${#system_info} - 2 ))
    (( padding < 1 )) && padding=1
    printf "|  %s%*s %s |\n" "$quit" $padding "" "$system_info"

    separator_dots
}

menu_error() { echo ""; echo "  ❌ $1"; echo ""; read -rp "  $(t menu.press_enter)"; }

# Yes/no before running something: Enter means no
menu_confirm() {
    local r
    read -rp "  $1 $(t ask.no_hint): " r
    lang_is_yes "$r"
}
menu_valid_num() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= $2 )); }

# Prompt helpers
menu_prompt_input() {
    local a; echo -n "  $1 [${2:-}]: "; read -r a
    [[ -z "$a" ]] && a="${2:-}"; echo "$a"
}

# Answers are always "yes" or "no" for the scripts, whatever language was typed
menu_prompt_yesno() {
    local a hint; hint="$(t ask.yes_hint)"; [[ "${2:-y}" == n* ]] && hint="$(t ask.no_hint)"
    while true; do
        echo -n "  $1 ${hint}: "; read -r a
        [[ -z "$a" ]] && a="${2:-y}"
        { lang_is_yes "$a" || lang_is_no "$a"; } && break
        echo "  $(t ask.yesno_again)"
    done
    lang_is_yes "$a" && echo "yes" || echo "no"
}

# ============================================================================
# Helper Functions
# ============================================================================

# Category keys, sorted by the name shown in the current language
get_categories() {
    local -n ref=$1; ref=()
    local k n d
    while IFS=$'\t' read -r k n d; do [[ -n "$k" ]] && ref+=("$k"); done < <(yaml_category_rows)
}

get_scripts() {
    local -n ref=$1; ref=(); local src="$2"
    while IFS= read -r s; do
        [[ -n "$s" ]] && yaml_os_compatible "$s" "$OS_DISTRO" "$OS_FAMILY" && [[ -f "$(yaml_script_path "$s")" ]] && ref+=("$s")
    done <<< "$src"
    # Sort alphabetically
    IFS=$'\n' read -d '' -r -a ref < <(printf '%s\n' "${ref[@]}" | sort) || true
}

# Search all ulh scripts by name, description and category.
# Fills the array named by $1 with "name|description|category" entries.
get_search_results() {
    local -n ref=$1; ref=(); local term="$2"
    local -a names descs cats base
    mapfile -t names < <(yaml_scripts)
    mapfile -t descs < <(yaml_all_descriptions)
    mapfile -t cats  < <(yaml_all_categories)
    # the English base text as well: "browser" finds it in every language
    mapfile -t base  < <(yaml_all_descriptions_base)

    local i n d c hay
    local needle="${term,,}"
    for i in "${!names[@]}"; do
        n="${names[$i]}"
        [[ -n "$n" ]] || continue
        d="${descs[$i]}"; [[ "$d" == "null" ]] && d=""
        c="${cats[$i]}";  [[ "$c" == "null" ]] && c=""
        # substring match without forking (case-insensitive, no regex surprises),
        # the expensive OS check runs only for hits
        hay="${n} ${d} ${c} ${base[$i]:-}"
        [[ "${hay,,}" == *"$needle"* ]] || continue
        yaml_os_compatible "$n" "$OS_DISTRO" "$OS_FAMILY" || continue
        [[ -f "$(yaml_script_path "$n")" ]] && ref+=("${n}|${d}|${c}")
    done
}

# ============================================================================
# Menu Display Functions
# ============================================================================

menu_show_repositories() {
    menu_clear
    menu_header "ulh - unknown linux helper" "${ulh_VERSION}"
    
    local i=1
    # Always show ulh system scripts
    printf "|  %2d) ulh - unknown linux helper\n" $i
    ((i++))
    
    # Show enabled custom repositories
    local repo_names
    repo_names=$(repo_list_enabled "${ulh_DIR}")
    while IFS= read -r repo_name; do
        [[ -z "$repo_name" ]] && continue
        local repo_display_name=$(repo_get_name "${ulh_DIR}/config/repo.yaml" "$repo_name")
        printf "|  %2d) %s\n" $i "$repo_display_name"
        ((i++))
    done <<< "$repo_names"
    
    menu_footer 0 1
}

# Show ulh system scripts (categories), names and descriptions in the current language
menu_show_main() {
    menu_clear
    menu_header "ulh - unknown linux helper" "${ulh_VERSION}"
    local -a rows=()
    local k n d w=20
    while IFS=$'\t' read -r k n d; do
        [[ -n "$k" ]] || continue
        rows+=("${n}"$'\t'"${d}")
        (( ${#n} > w && ${#n} <= 30 )) && w=${#n}
    done < <(yaml_category_rows)
    local i=1 r col
    for r in "${rows[@]}"; do
        n="${r%%$'\t'*}"; d="${r#*$'\t'}"
        if [[ -n "$d" && "$d" != "null" ]]; then
            menu_pad col "$n" "$w"
            printf "|  %2d) %s - %s\n" $i "$col" "$d"
        else
            printf "|  %2d) %s\n" $i "$n"
        fi
        ((i++))
    done
    
    # Show back button only if coming from repo menu
    if [[ "$CONTEXT_FROM" == "repo" ]]; then
        menu_footer 1 1
    else
        menu_footer 0 1
    fi
}

menu_show_category() {
    menu_clear
    menu_header "$(t menu.category "$(yaml_category_name "$1")")"
    local -a scripts; get_scripts scripts "$(yaml_scripts_by_cat "$1")"
    if (( ${#scripts[@]} == 0 )); then 
        echo "|  $(t menu.no_scripts)"
    else 
        local i=1; for s in "${scripts[@]}"; do 
            printf "|  %2d) %-20s - %s\n" $i "$s" "$(yaml_desc "$s")"
            ((i++))
        done
    fi
    menu_footer 1 1
}

menu_show_search() {
    local term="$1"; shift
    menu_clear
    menu_header "$(t menu.search_title "$term")"
    if (( $# == 0 )); then
        echo "|  $(t menu.search_none "$term")"
        echo "|"
        echo "|  $(t menu.search_where)"
    else
        # columns: 2 + 16 + 26 + 28 = 78 chars, so the box stays at 80
        local i=1 e n d c
        for e in "$@"; do
            n="${e%%|*}"; d="${e#*|}"; c="${d#*|}"; d="${d%%|*}"
            if (( ${#n} > 16 )); then n="${n:0:14}.."; fi
            if (( ${#c} > 26 )); then c="${c:0:24}.."; fi
            if (( ${#d} > 28 )); then d="${d:0:26}.."; fi
            menu_pad n "$n" 16; menu_pad c "$c" 26
            printf "|  %2d) %s %s %s\n" $i "$n" "$c" "$d"
            ((i++))
        done
    fi
    menu_footer 1 1
}

menu_show_actions() {
    menu_clear
    menu_header "$1 - $(yaml_desc "$1")"
    local count=$(yaml_action_count "$1"); [[ -z "$count" || "$count" == "null" ]] && count=0
    if (( count == 0 )); then 
        echo "|  $(t menu.no_actions)"
    else 
        for ((i=0; i<count; i++)); do
            local n=$(yaml_action_name "$1" $i) d=$(yaml_action_description "$1" $i)
            if [[ -n "$d" && "$d" != "null" ]]; then
                printf "|  %2d) %-20s - %s\n" $((i+1)) "$n" "$d"
            else
                printf "|  %2d) %s\n" $((i+1)) "$n"
            fi
        done
    fi
    menu_footer 1
}

# Show custom repo scripts
menu_show_custom_repo() {
    local repo_name="$1"
    local repo_path="$2"
    local repo_display_name=$(repo_get_name "${ulh_DIR}/config/repo.yaml" "$repo_name")
    
    menu_clear
    menu_header "$(t menu.custom "$repo_display_name")"
    
    # Load config.yaml from repo (custom repos have their own config.yaml)
    if [[ ! -f "$repo_path/config.yaml" ]]; then
        echo "|  $(t menu.custom_noconfig "$repo_path")"
        menu_footer 1
        return 1
    fi
    
    # Get scripts from this repo's config.yaml
    local -a scripts=()
    while IFS= read -r script_name; do
        [[ -n "$script_name" ]] && scripts+=("$script_name")
    done <<< "$(yq_eval ".scripts | keys | .[]" "$repo_path/config.yaml" 2>/dev/null)"
    
    if (( ${#scripts[@]} == 0 )); then
        echo "|  $(t menu.custom_none)"
    else
        local i=1; for s in "${scripts[@]}"; do 
            local desc=$(yq_eval "$(yq_l10n ".scripts.$s.description")" "$repo_path/config.yaml" 2>/dev/null)
            printf "|  %2d) %-20s - %s\n" $i "$s" "$desc"
            ((i++))
        done
    fi
    
    menu_footer 1
}

menu_show_custom_repo_actions() {
    local repo_name="$1"
    local repo_path="$2"
    local script_name="$3"
    local repo_display_name=$(repo_get_name "${ulh_DIR}/config/repo.yaml" "$repo_name")
    
    menu_clear
    menu_header "$(t menu.custom "$repo_display_name - $script_name")"
    
    # Get actions from repo's config.yaml
    local count
    count=$(yq_eval ".scripts.$script_name.actions | length" "$repo_path/config.yaml" 2>/dev/null)
    [[ -z "$count" || "$count" == "null" ]] && count=0
    
    if (( count == 0 )); then 
        echo "|  $(t menu.no_actions)"
    else 
        for ((i=0; i<count; i++)); do
            local n=$(yq_eval ".scripts.$script_name.actions[$i].name" "$repo_path/config.yaml" 2>/dev/null)
            local d=$(yq_eval "$(yq_l10n ".scripts.$script_name.actions[$i].description")" "$repo_path/config.yaml" 2>/dev/null)
            [[ -n "$d" && "$d" != "null" ]] && printf "|  %2d) %-20s - %s\n" $((i+1)) "$n" "$d" || printf "|  %2d) %s\n" $((i+1)) "$n"
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
    custom_repos=$(repo_list_enabled "${ulh_DIR}")
    
    if [[ -n "$custom_repos" ]]; then
        # Show repository selector
        menu_repositories
    else
        # Show ulh scripts directly (no repos)
        menu_ulh_scripts
    fi
}

menu_repositories() {
    while true; do
        menu_show_repositories
        
        # Count menu items: ulh + custom repos
        local i=1
        local -a choices=("ulh")  # First choice is ulh
        ((i++))
        
        while IFS= read -r repo_name; do
            [[ -z "$repo_name" ]] && continue
            choices+=("$repo_name")
            ((i++))
        done <<< "$(repo_list_enabled "${ulh_DIR}")"
        
        local max=$((i-1))
        
        echo ""; local input; read -rp "  $(t menu.choose) " input || exit 0
        case "$input" in
            q|Q) echo "  $(t menu.goodbye)"; exit 0 ;;
            l|L) lang_switch ;;
            s|S) menu_ask_search ;;
            /*) menu_search "${input#/}" ;;
            [0-9]*)
                if menu_valid_num "$input" $max; then
                    local choice="${choices[$((input-1))]}"
                    if [[ "$choice" == "ulh" ]]; then
                        CONTEXT_FROM="repo"
                        menu_ulh_scripts
                    else
                        local repo_path=$(repo_get_path "${ulh_DIR}/config/repo.yaml" "$choice")
                        menu_custom_repo_scripts "$choice" "$repo_path"
                    fi
                else menu_error "$(t menu.invalid_range "$max")" ; fi ;;
            "") ;; *) menu_error "$(t menu.invalid)" ;;
        esac
    done
}

menu_ulh_scripts() {
    while true; do
        menu_show_main
        local -a cats; get_categories cats; local max=${#cats[@]}
        echo ""; local input; read -rp "  $(t menu.choose) " input || return
        case "$input" in
            q|Q) exit 0 ;;
            l|L) lang_switch ;;
            b|B) CONTEXT_FROM="none"; return ;;
            s|S) menu_ask_search ;;
            /*) menu_search "${input#/}" ;;
            [0-9]*) menu_valid_num "$input" $max && menu_category "${cats[$((input-1))]}" || menu_error "$(t menu.invalid_range "$max")" ;;
            "") ;; *) menu_error "$(t menu.invalid)" ;;
        esac
    done
}

menu_category() {
    while true; do
        menu_show_category "$1"
        local -a scripts; get_scripts scripts "$(yaml_scripts_by_cat "$1")"; local max=${#scripts[@]}
        echo ""; local input; read -rp "  $(t menu.choose) " input || return
        case "$input" in
            q|Q) exit 0 ;; b|B) return ;;
            l|L) lang_switch ;;
            s|S) menu_ask_search ;;
            /*) menu_search "${input#/}" ;;
            [0-9]*) menu_valid_num "$input" $max && menu_actions "${scripts[$((input-1))]}" || menu_error "$(t menu.invalid_range "$max")" ;;
            "") ;; *) menu_error "$(t menu.invalid)" ;;
        esac
    done
}

# Ask for a search term, then show the results. Returns without searching
# if the user just presses Enter.
menu_ask_search() {
    local term
    echo ""
    read -rp "  $(t menu.search_ask) " term || return 0
    [[ -n "$term" ]] || return 0
    menu_search "$term"
}

# Search results: pick a number to jump straight into that script's actions
menu_search() {
    local term="$1"
    [[ -n "$term" ]] || return 0

    while true; do
        local -a results; get_search_results results "$term"
        menu_show_search "$term" "${results[@]}"
        local max=${#results[@]}

        echo ""; local input; read -rp "  $(t menu.choose) " input || return
        case "$input" in
            q|Q) exit 0 ;;
            l|L) lang_switch ;;
            b|B) return ;;
            s|S)
                local new_term
                echo ""; read -rp "  $(t menu.search_again) " new_term || return
                [[ -n "$new_term" ]] && term="$new_term"
                ;;
            /*)
                [[ -n "${input#/}" ]] && term="${input#/}"
                ;;
            [0-9]*)
                if (( max > 0 )) && menu_valid_num "$input" $max; then
                    local entry="${results[$((input-1))]}"
                    menu_actions "${entry%%|*}"
                else menu_error "$(t menu.invalid_range "$max")"; fi ;;
            "") ;; *) menu_error "$(t menu.invalid)" ;;
        esac
    done
}

menu_actions() {
    while true; do
        menu_show_actions "$1"
        local count=$(yaml_action_count "$1"); [[ -z "$count" || "$count" == "null" ]] && count=0
        echo ""; local input; read -rp "  $(t menu.choose) " input || return
        case "$input" in
            q|Q) exit 0 ;; b|B) return ;;
            l|L) lang_switch ;;
            [0-9]*)
                if (( count > 0 )) && menu_valid_num "$input" $count; then
                    local idx=$((input-1))
                    execute_action "$1" $idx
                else menu_error "$(t menu.invalid_range "$count")"; fi ;;
            "") ;; *) menu_error "$(t menu.invalid)" ;;
        esac
    done
}

menu_custom_repo_scripts() {
    local repo_name="$1"
    local repo_path="$2"
    
    while true; do
        menu_show_custom_repo "$repo_name" "$repo_path" || return
        
        # Get scripts from repo's config.yaml
        local -a scripts=()
        while IFS= read -r script_name; do
            [[ -n "$script_name" ]] && scripts+=("$script_name")
        done <<< "$(yq_eval ".scripts | keys | .[]" "$repo_path/config.yaml" 2>/dev/null)"
        
        local max=${#scripts[@]}
        echo ""; local input; read -rp "  $(t menu.choose) " input || return
        case "$input" in
            q|Q) exit 0 ;;
            l|L) lang_switch ;;
            b|B) return ;;
            [0-9]*)
                if menu_valid_num "$input" $max; then
                    menu_custom_repo_actions "$repo_name" "$repo_path" "${scripts[$((input-1))]}"
                else menu_error "$(t menu.invalid_range "$max")"; fi ;;
            "") ;; *) menu_error "$(t menu.invalid)" ;;
        esac
    done
}

menu_custom_repo_actions() {
    local repo_name="$1"
    local repo_path="$2"
    local script_name="$3"
    
    while true; do
        menu_show_custom_repo_actions "$repo_name" "$repo_path" "$script_name"
        
        # Get actions from repo's config.yaml
        local count
        count=$(yq_eval ".scripts.$script_name.actions | length" "$repo_path/config.yaml" 2>/dev/null)
        [[ -z "$count" || "$count" == "null" ]] && count=0
        
        echo ""; local input; read -rp "  $(t menu.choose) " input || return
        case "$input" in
            q|Q) exit 0 ;;
            l|L) lang_switch ;;
            b|B) return ;;
            [0-9]*)
                if (( count > 0 )) && menu_valid_num "$input" $count; then
                    execute_custom_repo_action "$repo_name" "$repo_path" "$script_name" $((input-1))
                else menu_error "$(t menu.invalid_range "$count")"; fi ;;
            "") ;; *) menu_error "$(t menu.invalid)" ;;
        esac
    done
}

#!/bin/bash
# ulh - YAML Parser (wraps bundled yq)

# Load colors from centralized library
source "${BASH_SOURCE%/*}/colors.sh"

# Locate architecture-specific yq binary (bundled in vendor/yq, see THIRD-PARTY.md)
init_yq() {
    local yqdir="${ulh_DIR}/vendor/yq"
    case "$(uname -m)" in
        x86_64)        YQ="${yqdir}/yq-amd64" ;;
        aarch64|arm64) YQ="${yqdir}/yq-arm64" ;;
        armv7l)        YQ="${yqdir}/yq-arm" ;;
        i686)          YQ="${yqdir}/yq-386" ;;
        *) die "Unsupported architecture: $(uname -m)" ;;
    esac
    # Auto-fix missing execute permission
    [[ -f "$YQ" && ! -x "$YQ" ]] && chmod +x "$YQ" 2>/dev/null
    [[ -x "$YQ" ]] || die "yq not found/executable: $YQ"
}
init_yq

# yq for the other modules
get_yq()  { echo "$YQ"; }
yq_eval() { "$YQ" eval "$@"; }

YAML_FILE=""

# Load a YAML file (path without extension, relative to ulh_DIR)
yaml_load() {
    YAML_FILE="${ulh_DIR}/${1}.yaml"
    [[ -f "$YAML_FILE" ]] || { msg_err "Config not found: $YAML_FILE"; return 1; }
    debug "Config loaded: $YAML_FILE"
    return 0
}

# Generic query (returns default if null/empty)
yq_get() {
    local result; result=$("$YQ" eval "$1" "$YAML_FILE" 2>/dev/null)
    [[ -z "$result" || "$result" == "null" ]] && echo "${2:-}" || echo "$result"
}

yq_list() { "$YQ" eval "$1" "$YAML_FILE" 2>/dev/null; }

# Categories
yaml_categories()  { yq_list '[.scripts[].category] | unique | .[]'; }

# Scripts
yaml_scripts()     { yq_list '.scripts | keys | .[]'; }
yaml_scripts_by_cat() { yq_list ".scripts | to_entries | map(select(.value.category == \"${1}\")) | .[].key"; }

# Search index: descriptions and categories in the same order as yaml_scripts,
# so the three lists can be zipped by index (one yq call each instead of 3x96)
yaml_all_descriptions() { yq_list '[.scripts[].description] | .[]'; }
yaml_all_categories()   { yq_list '[.scripts[].category] | .[]'; }

# Script info
yaml_info()        { yq_get ".scripts.${1}.${2}"; }
# Scripts live in scripts/ next to the catalog
yaml_script_path() {
    local file; file=$(yq_get ".scripts.${1}.file")
    local dir; dir="${YAML_FILE%/*}/$(yq_get ".script_dir" "scripts")"
    [[ -n "$file" ]] && echo "${dir}/${file}" || echo "${dir}/${1}.sh"
}

# OS compatibility (priority: os_only > os_family > os_exclude)
yaml_get_script_os_family()  { yq_list ".scripts.${1}.os_family // [] | .[]"; }
yaml_get_script_os_exclude() { yq_list ".scripts.${1}.os_exclude // [] | .[]"; }
yaml_get_script_os_only()    { yq_list ".scripts.${1}.os_only // [] | [.] | flatten | .[]"; }

yaml_os_compatible() {
    local script="$1" distro="$2" family="$3"

    # os_only: whitelist — only these distros allowed
    local only; only=$(yaml_get_script_os_only "$script")
    if [[ -n "$only" ]]; then
        echo "$only" | grep -qx "$distro" && return 0 || return 1
    fi

    # os_family: must match family
    local fam; fam=$(yaml_get_script_os_family "$script")
    [[ -n "$fam" ]] && { echo "$fam" | grep -qx "$family" || return 1; }

    # os_exclude: blacklist
    local excl; excl=$(yaml_get_script_os_exclude "$script")
    [[ -n "$excl" ]] && { echo "$excl" | grep -qx "$distro" && return 1; }

    return 0
}

# Actions
yaml_action_count()       { yq_list ".scripts.${1}.actions | length"; }
yaml_action_name()        { yq_get ".scripts.${1}.actions[${2}].name"; }
yaml_action_param()       { yq_get ".scripts.${1}.actions[${2}].parameter"; }
yaml_action_description() { yq_get ".scripts.${1}.actions[${2}].description"; }

# Action prompts
yaml_prompt_count() { yq_list ".scripts.${1}.actions[${2}].prompts // [] | length"; }
yaml_prompt_field() { yq_get ".scripts.${1}.actions[${2}].prompts[${3}].${4}"; }
yaml_prompt_var()   { yq_get ".scripts.${1}.actions[${2}].prompts[${3}].variable"; }
yaml_prompt_opts()  { yq_list ".scripts.${1}.actions[${2}].prompts[${3}].options // [] | .[]"; }

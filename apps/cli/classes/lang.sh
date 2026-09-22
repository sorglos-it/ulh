#!/bin/bash
# ulh - Languages: detect, switch, texts
#
# Five languages, one file each in lang/<xx>.yaml. Which one applies, in this
# order: --lang on the command line, config/settings.yaml (the menu key l saves
# the choice there), else the language of the system ($LANG). A text missing in
# a language comes in English.
#
# The catalog carries its own translations: description is the English base
# text, descriptionDE, descriptionFR ... translate it - the same for question
# and for the category names (categories: <name>: nameDE).

ULH_LANGUAGES=(de en fr it es)
ULH_LANG="en"
ULH_LANG_SUFFIX="EN"
ULH_LANG_SOURCE="system"
declare -gA ULH_TEXT=() ULH_TEXT_EN=()

lang_valid() {
    local l
    for l in "${ULH_LANGUAGES[@]}"; do [[ "$1" == "$l" ]] && return 0; done
    return 1
}

# The system language. ulh.sh switches to C.UTF-8 for its own output and keeps
# what was set before in ULH_SYS_LOCALE (de_DE.UTF-8 -> de). "C" or nothing is
# no language: then the setting of the installation counts. That also covers
# the restart after an update from a ulh that had already set C.UTF-8.
lang_system() {
    local l="${ULH_SYS_LOCALE:-}" f v
    if [[ -z "$l" || "$l" == C || "$l" == C.* || "$l" == POSIX ]]; then
        l=""
        for f in /etc/default/locale /etc/locale.conf; do
            [[ -r "$f" ]] || continue
            for v in LC_ALL LC_MESSAGES LANG; do
                l="$(grep -m1 -E "^[[:space:]]*${v}=" "$f" 2>/dev/null)"
                l="${l#*=}"; l="${l//\"/}"; l="${l//\'/}"
                [[ -n "$l" ]] && break 2
            done
        done
    fi
    l="${l%%_*}"; l="${l%%.*}"; l="${l,,}"
    if lang_valid "$l"; then echo "$l"; else echo "en"; fi
}

lang_settings_file() { echo "${ulh_DIR}/config/settings.yaml"; }

lang_saved() {
    local f; f="$(lang_settings_file)"
    [[ -f "$f" ]] || return 0
    local l; l="$("$YQ" eval '.language // ""' "$f" 2>/dev/null)"
    l="${l,,}"
    lang_valid "$l" && echo "$l"
}

# Read lang/<xx>.yaml into the associative array named by $2 - one yq call.
_lang_read() {
    local -n _ziel=$2
    _ziel=()
    local f="${ulh_DIR}/lang/$1.yaml" k v
    [[ -f "$f" ]] || return 1
    while IFS=$'\t' read -r k v; do
        [[ -n "$k" ]] && _ziel["$k"]="$v"
    done < <("$YQ" eval 'to_entries | .[] | .key + "\t" + .value' "$f" 2>/dev/null)
}

lang_set() {
    local l="${1,,}"
    lang_valid "$l" || l="en"
    (( ${#ULH_TEXT_EN[@]} > 0 )) || _lang_read en ULH_TEXT_EN
    if [[ "$l" == "en" ]]; then ULH_TEXT=(); else _lang_read "$l" ULH_TEXT; fi
    ULH_LANG="$l"
    ULH_LANG_SUFFIX="${l^^}"
    export ULH_LANG
}

# $1 = value of --lang, empty if not given
lang_init() {
    local l="${1,,}"
    if [[ -n "$l" ]] && lang_valid "$l"; then
        ULH_LANG_SOURCE="parameter"
    else
        l="$(lang_saved)"
        ULH_LANG_SOURCE="settings"
        if [[ -z "$l" ]]; then l="$(lang_system)"; ULH_LANG_SOURCE="system"; fi
    fi
    lang_set "$l"
}

# The next language for the menu key l - after the last comes the first.
lang_next() {
    local i
    for i in "${!ULH_LANGUAGES[@]}"; do
        if [[ "${ULH_LANGUAGES[$i]}" == "$ULH_LANG" ]]; then
            echo "${ULH_LANGUAGES[$(( (i + 1) % ${#ULH_LANGUAGES[@]} ))]}"
            return
        fi
    done
    echo "en"
}

# Save the language in config/settings.yaml. Only the line "language:" is
# replaced - comments and everything else stay as they are.
lang_save() {
    local f; f="$(lang_settings_file)"
    [[ -f "$f" ]] || cp "${f}.example" "$f" 2>/dev/null || printf 'language:\n' > "$f" 2>/dev/null || return 1
    if grep -q '^language:' "$f"; then
        sed -i "s/^language:.*/language: $1/" "$f"
    else
        printf 'language: %s\n' "$1" >> "$f"
    fi
}

# Switch to the next language and remember it (menu key l)
lang_switch() {
    local l; l="$(lang_next)"
    lang_set "$l"
    lang_save "$l"
    ULH_LANG_SOURCE="settings"
}

# Text for a key in the current language, {0} {1} ... replaced by the further
# arguments:   t menu.search_title "$term"
t() {
    local key="$1"; shift
    local s="${ULH_TEXT[$key]:-${ULH_TEXT_EN[$key]:-$key}}" i=0 a
    for a in "$@"; do
        s="${s//"{$i}"/"$a"}"
        i=$((i + 1))
    done
    printf '%s' "$s"
}

# yq expression for a text field in the current language, English base as
# fallback:  yq_l10n '.scripts.curl.description'
#   -> (.scripts.curl.descriptionDE // .scripts.curl.description)
yq_l10n() { printf '(%s%s // %s)' "$1" "$ULH_LANG_SUFFIX" "$1"; }

# Yes or no, typed in any of the five languages: j, y, o (oui) and s (si) mean yes.
lang_is_yes() { [[ "${1,,}" =~ ^(y|yes|j|ja|o|oui|s|si|sì|sí)$ ]]; }
lang_is_no()  { [[ "${1,,}" =~ ^(n|no|nein|non)$ ]]; }

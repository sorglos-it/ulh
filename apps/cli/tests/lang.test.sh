# Five languages: language files, catalog translations, system language,
# --lang, the menu key l and yes/no in every language. Sourced by run.sh.

ldir="${ULH}/apps/cli/lang"
cat_file="${ULH}/apps/cli/assets/catalog.yaml"
settings="${ULH}/apps/cli/config/settings.yaml"
start() { ( cd "$ULH" && printf '%b' "$1" | bash apps/cli/ulh.sh --no-update "${@:2}" 2>&1 ); }

# {0} {1} ... of a text, counted: "0:1 1:1 "
places() {
    local s="$1" d x out=""
    for d in 0 1 2 3 4 5; do
        x="${s//"{$d}"/}"
        (( ${#x} < ${#s} )) && out+="${d}:$(( (${#s} - ${#x}) / 3 )) "
    done
    echo "$out"
}
# key<TAB>placeholders for every text of a language file
lang_places() {
    local k v
    while IFS=$'\t' read -r k v; do printf '%s\t%s\n' "$k" "$(places "$v")"; done \
        < <("$YQ" 'to_entries | .[] | .key + "\t" + .value' "$1")
}

en="$(lang_places "${ldir}/en.yaml")"
bad=0
for l in de fr it es; do
    if [[ ! -f "${ldir}/${l}.yaml" ]]; then bad=$((bad + 1)); echo "    missing: lang/${l}.yaml"; continue; fi
    [[ "$(lang_places "${ldir}/${l}.yaml")" == "$en" ]] \
        || { bad=$((bad + 1)); echo "    lang/${l}.yaml: keys, order or {0} {1} ... differ from en.yaml"; }
done
check "language files: same keys and {0} {1} ... as en.yaml" test "$bad" = 0

missing="$("$YQ" '[.. | select(tag == "!!map") | select(
    (has("description") and ((has("descriptionDE") and has("descriptionES") and has("descriptionIT") and has("descriptionFR")) | not)) or
    (has("question") and ((has("questionDE") and has("questionES") and has("questionIT") and has("questionFR")) | not)))] | length' "$cat_file")"
nocat="$("$YQ" '[.categories[] | select((has("nameDE") and has("nameES") and has("nameIT") and has("nameFR")) | not)] | length' "$cat_file")"
check "catalog: every description, question and category in all languages" test "${missing}${nocat}" = "00"

# System language, --lang, and --lang with a language ulh does not know
out="$(cd "$ULH" && printf 'q\n' | ULH_SYS_LOCALE= LANG=de_DE.UTF-8 bash apps/cli/ulh.sh --no-update 2>&1)"
check "system language German: German menu" grep -q 'Grundwerkzeuge' <<< "$out"
sys="$(cd "${ULH}/apps/cli" && ulh_DIR="$PWD" ULH_SYS_LOCALE=fr_FR.UTF-8 bash -c 'source classes/lang.sh; lang_system')"
check "fr_FR.UTF-8 -> fr" test "$sys" = fr
out="$(start 'q\n' --lang fr)"
check "--lang fr: French menu" grep -q 'Outils essentiels' <<< "$out"
out="$(start '/curl\nb\nq\n' --lang de)"
check "--lang de: German descriptions in the search" grep -q 'Werkzeug für HTTP-Anfragen' <<< "$out"
out="$(start '/requests\nb\nq\n' --lang de)"
check "search finds English words in every language" grep -q 'curl' <<< "$out"
out="$(cd "$ULH" && bash apps/cli/ulh.sh --lang xx 2>&1)"; rc=$?
check "--lang xx: message and exit 1" test "$rc" = 1 -a -n "$(grep 'xx' <<< "$out")"
out="$(cd "$ULH" && bash apps/cli/ulh.sh --lang 2>&1)"; rc=$?
check "--lang without a language: exit 1" test "$rc" = 1

# Key l: next language (en -> fr), saved in config/settings.yaml
printf 'language:\n' > "$settings"
out="$(start 'l\nq\n')"
check "key l switches to the next language" grep -q 'Français' <<< "$out"
check "key l saves it in config/settings.yaml" grep -qx 'language: fr' "$settings"
out="$(start 'q\n')"
check "the saved language counts on the next start" grep -q 'Outils essentiels' <<< "$out"
out="$(start 'q\n' --lang en)"
check "--lang beats the saved language" grep -q 'Essential Tools' <<< "$out"
printf 'language:\n' > "$settings"

# Yes/no typed in any language; the script always gets yes or no
yn="$(cd "${ULH}/apps/cli" && ulh_DIR="$PWD" bash -c 'source classes/lang.sh
    for a in j ja Ja y yes o oui s si sí; do lang_is_yes "$a" || echo "not yes: $a"; done
    for a in n N no nein non; do lang_is_no "$a" || echo "not no: $a"; done
    for a in x jn maybe; do lang_is_yes "$a" && echo "yes: $a"; lang_is_no "$a" && echo "no: $a"; done' 2>&1)"
check "yes/no in all five languages" test -z "$yn"
pt="$(cd "${ULH}/apps/cli" && printf 'ja\n' | ulh_DIR="$PWD" bash -c 'for l in core yaml lang execute; do source classes/$l.sh; done
    lang_set de; prompt_by_type "Wirklich? (yes/no)" yes/no no' 2> "${TMP}/prompt.txt")"
check "German question: 'ja' gives the script yes" test "$pt" = "yes"
check "German question shows [j/N], not (yes/no)" grep -q 'Wirklich?.*j/N' "${TMP}/prompt.txt"
check "German question without (yes/no)" not grep -q 'yes/no' "${TMP}/prompt.txt"

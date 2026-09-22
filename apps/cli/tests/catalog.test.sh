# Catalog and script files match, every script answers an unknown action
# with its usage. Sourced by run.sh.

cat_file="${ULH}/apps/cli/assets/catalog.yaml"
sdir="${ULH}/apps/cli/assets/scripts"
mapfile -t names < <("$YQ" '.scripts | keys | .[]' "$cat_file")

missing=0
bad=0
declare -A listed=()
for s in "${names[@]}"; do
    f="$("$YQ" ".scripts.\"${s}\".file" "$cat_file")"
    listed["$f"]=1
    if [[ ! -f "${sdir}/${f}" ]]; then
        missing=$((missing + 1)); echo "    no file for ${s}: ${f}"
        continue
    fi
    out="$(cd "$TMP" && bash "${sdir}/${f}" zz-test < /dev/null 2>&1)"
    rc=$?
    if [[ "$rc" != 1 || "$out" != *"Unknown action"* ]]; then
        bad=$((bad + 1)); echo "    ${s}: exit ${rc}"
    fi
done
orphans=0
for f in "$sdir"/*.sh; do
    [[ -n "${listed[${f##*/}]:-}" ]] || { orphans=$((orphans + 1)); echo "    not in catalog: ${f##*/}"; }
done

check "catalog has scripts (${#names[@]})" test "${#names[@]}" -gt 0
check "every catalog entry has its script" test "$missing" = 0
check "every script has a catalog entry" test "$orphans" = 0
check "every script answers an unknown action (exit 1)" test "$bad" = 0

# Every shell file parses (bash -n). Sourced by run.sh.

n=0
bad=0
while IFS= read -r f; do
    n=$((n + 1))
    bash -n "$f" 2>/dev/null || { bad=$((bad + 1)); echo "    syntax error: ${f#"$ULH"/}"; }
done < <(find "$ULH" -name '*.sh' -not -path "${ULH}/.git/*" | sort)
check "bash -n on all ${n} shell files" test "$bad" = 0

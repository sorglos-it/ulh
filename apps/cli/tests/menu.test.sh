# The menu starts, navigates, searches and quits. Sourced by run.sh.

menu() { ( cd "$ULH" && printf '%b' "$1" | bash apps/cli/ulh.sh --no-update 2>&1 ); }

out="$(menu 'q\n')"; rc=$?
check "menu starts and quits (exit 0)" test "$rc" = 0
check "shows the version" grep -q "VERSION: $(tr -d '[:space:]' < "${ULH}/apps/cli/VERSION")" <<< "$out"
check "shows 16 categories" test "$(grep -cE '^\|  +[0-9]+\) ' <<< "$out")" = 16

out="$(menu '5\n1\nb\nb\nq\n')"
check "category -> script -> actions" grep -q 'build-essential - ' <<< "$out"

out="$(menu '/spool\nb\ns\nnginx\nb\nq\n')"
check "search with /term finds spoolman" grep -q 'spoolman' <<< "$out"
check "search with s finds nginx" grep -q 'Search: nginx' <<< "$out"

out="$(cd "$ULH" && bash apps/cli/ulh.sh --help 2>&1)"; rc=$?
check "--help (exit 0)" test "$rc" = 0 -a -n "$(grep 'Usage' <<< "$out")"
out="$(cd "$ULH" && bash apps/cli/ulh.sh --bogus 2>&1)"; rc=$?
check "unknown option (exit 1)" test "$rc" = 1

out="$(cd / && printf 'q\n' | bash "${ULH}/ulh.sh" --no-update 2>&1)"; rc=$?
check "old start command ulh.sh forwards (exit 0)" test "$rc" = 0

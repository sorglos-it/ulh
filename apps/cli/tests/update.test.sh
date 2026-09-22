# Self-update against a local "GitHub" (remote.git). Sourced by run.sh.

U="${TMP}/update"
W="${TMP}/work"
git clone -q "${TMP}/remote.git" "$U"
git clone -q "${TMP}/remote.git" "$W"
publish() {
    echo "$1" >> "$W/.test-change"
    git -C "$W" add .test-change && git -C "$W" commit -qm "$1" && git -C "$W" push -q origin main
}

publish one
out="$(bash "$U/apps/cli/ulh.sh" --check-update 2>&1)"
check "--check-update sees the update" grep -q 'Updates available' <<< "$out"
out="$(bash "$U/apps/cli/ulh.sh" --update 2>&1)"
check "--update pulls it" grep -q 'Update successful' <<< "$out"
out="$(bash "$U/apps/cli/ulh.sh" --check-update 2>&1)"
check "--check-update: up to date afterwards" grep -q 'up to date' <<< "$out"

chmod 755 "$U/.test-change"                 # a local chmod must not block updates
publish two
out="$( cd "$U" && printf 'q\n' | bash ulh.sh 2>&1 )"; rc=$?
check "start: updates and restarts" grep -q 'restarting' <<< "$out"
check "start: then shows the menu (exit 0)" test "$rc" = 0 -a -n "$(grep 'Essential Tools' <<< "$out")"
check "start: new commit is there" grep -q two "$U/.test-change"

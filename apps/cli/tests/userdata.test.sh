# Your files: first start of a fresh copy, and the move from the old custom/
# folder of installations before 2026-09-22. Sourced by run.sh.

# ---- fresh copy
F="${TMP}/fresh"
git clone -q "${TMP}/remote.git" "$F"
( cd "$F" && printf 'q\n' | bash apps/cli/ulh.sh --no-update ) > /dev/null 2>&1
check "fresh: repo.yaml from the template" cmp "$F/apps/cli/config/repo.yaml" "$F/apps/cli/config/repo.yaml.example"
check "fresh: demo repository created" test -f "$F/apps/cli/data/repos/demo-scripts/scripts/hello.sh"
out="$(bash "$F/apps/cli/data/repos/demo-scripts/scripts/hello.sh" zz 2>&1)"
check "fresh: demo script loads ../../../lib/bootstrap.sh" grep -q 'Unknown action: zz' <<< "$out"
check "fresh: no custom/ folder" test ! -e "$F/custom"

# ---- old installation
U="${TMP}/old"
git clone -q "${TMP}/remote.git" "$U"
old="${U}/custom"
mkdir -p "$old/keys" "$old/demo-scripts/scripts" "$old/tools/scripts"
# files old versions shipped in git
printf 'repositories:\n  demo-scripts:\n    name: "Demo Scripts"\n    path: "demo-scripts"\n' > "$old/repo.yaml"
cp "${U}/apps/cli/templates/demo-file-backup.sh" "$old/demo-scripts/scripts/file-backup.sh"
chmod 644 "$old/demo-scripts/scripts/file-backup.sh"
git -C "$U" add -f custom/repo.yaml custom/demo-scripts/scripts/file-backup.sh
git -C "$U" commit -qm "files of the old version"
# what the user and old ulh versions did with them
printf '  tools:\n    name: "My Tools"\n    path: "tools"\n    enabled:\n' >> "$old/repo.yaml"
chmod 755 "$old/demo-scripts/scripts/file-backup.sh"
printf 'scripts: {}\n' > "$old/answer.yaml"
printf 'KEY\n' > "$old/keys/id_test"
chmod 600 "$old/keys/id_test"
printf 'scripts:\n  tool:\n    description: "Tool"\n    path: "tool.sh"\n    actions:\n      - name: "go"\n        parameter: "go"\n' > "$old/tools/config.yaml"
cat > "$old/tools/scripts/tool.sh" <<'EOF'
#!/bin/bash
set -e
source "$(dirname "$0")/../../../lib/bootstrap.sh"
parse_parameters "$1"
case "$ACTION" in
    go) msg_ok "TOOL-OK" ;;
    *) print_usage tool && exit 1 ;;
esac
EOF
cp "$old/repo.yaml" "${TMP}/repo.saved"

out="$( cd "$U" && printf 'q\n' | bash apps/cli/ulh.sh --no-update 2>&1 )"
check "old: tells about the move" grep -q 'Your files moved' <<< "$out"
check "old: changed repo.yaml moved as it was" cmp "$U/apps/cli/config/repo.yaml" "${TMP}/repo.saved"
check "old: unchanged file-backup.sh removed (mode change ignored)" test ! -e "$old/demo-scripts/scripts/file-backup.sh"
check "old: answer.yaml moved" test -f "$U/apps/cli/config/answer.yaml"
check "old: key moved, still 600" test "$(stat -c %a "$U/apps/cli/data/keys/id_test" 2>/dev/null)" = 600
check "old: own repository moved" test -f "$U/apps/cli/data/repos/tools/scripts/tool.sh"
check "old: custom/ gone" test ! -e "$old"
check "old: own repository in the menu" grep -q 'My Tools' <<< "$out"
out="$(bash "$U/apps/cli/data/repos/tools/scripts/tool.sh" go 2>&1)"
check "old: own script still loads ../../../lib/bootstrap.sh" grep -q 'TOOL-OK' <<< "$out"
out="$( cd "$U" && printf 'q\n' | bash apps/cli/ulh.sh --no-update 2>&1 )"
check "old: second start moves nothing" not grep -q 'moved' <<< "$out"

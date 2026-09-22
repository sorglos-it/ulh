# build-essential and locate name the package they install or remove, and a
# failing package manager ends them with an error. Before 2026-09-22 they ran
# e.g. "apt-get install -y" without a package and reported success.
# Checked on the distribution the tests run on. Sourced by run.sh.

pm="${TMP}/pm"
pmlog="${TMP}/pm.log"
mkdir -p "$pm"
for p in apt-get dnf pacman zypper apk; do
    printf '#!/bin/bash\necho "${0##*/} $*" >> "%s"\nexit "${PM_EXIT:-0}"\n' "$pmlog" > "${pm}/${p}"
done
printf '#!/bin/bash\nexit 0\n' > "${pm}/updatedb"
cp "${pm}/updatedb" "${pm}/locate"
chmod +x "$pm"/*

# pm_run <exit code of the package manager> <script> <action>
pm_run() {
    : > "$pmlog"
    ( cd "$TMP" && PM_EXIT="$1" PATH="${pm}:${PATH}" bash "${ULH}/apps/cli/assets/scripts/${2}.sh" "$3" ) \
        < /dev/null > /dev/null 2>&1
}
# install or remove without a package name: the call ends with an option or the verb
nameless() { grep -E '( |^)(-y|--noconfirm|add|del|install|remove) *$' "$pmlog"; }
# any call besides refreshing the package lists
pm_changed() { grep -vqE '^(apt-get update|dnf check-update|pacman -Sy|zypper refresh|apk update)( |$)' "$pmlog"; }

no_name=0
no_error=0
for sa in "build-essential install" "build-essential update" "build-essential uninstall" \
          "locate install" "locate uninstall"; do
    read -r s a <<< "$sa"
    if pm_run 0 "$s" "$a" && ! pm_changed; then
        no_name=$((no_name + 1)); echo "    ${sa}: success without installing or removing"
    fi
    if [[ -n "$(nameless)" ]]; then
        no_name=$((no_name + 1)); echo "    ${sa}: $(nameless | head -1) - no package name"
    fi
    if pm_run 100 "$s" "$a"; then
        no_error=$((no_error + 1)); echo "    ${sa}: success although the package manager failed"
    fi
done
check "build-essential, locate: package manager gets a package name" test "$no_name" = 0
check "build-essential, locate: failing package manager = error" test "$no_error" = 0

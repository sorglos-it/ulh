#!/bin/bash
# ulh tests - run on Linux:  bash apps/cli/tests/run.sh
#
# Runs every *.test.sh in this folder against a copy of ulh in a temporary
# folder. sudo, package managers and the network are stubs: nothing gets
# installed, nothing outside the temporary folder changes.
set -u

TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "${TESTS}/../../.." && pwd)"          # the ulh folder
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASSED=0
FAILED=0

# check "what" command... - one line per check
check() {
    if "${@:2}" >/dev/null 2>&1; then
        PASSED=$((PASSED + 1)); echo "  ok    $1"
    else
        FAILED=$((FAILED + 1)); echo "  FAIL  $1"
    fi
}
not() { ! "$@"; }

# ---------------------------------------------------------------- stubs
STUBS="${TMP}/stubs"
mkdir -p "$STUBS"
for p in apt-get apt dnf yum pacman zypper apk snap systemctl service flatpak clear; do
    printf '#!/bin/bash\nexit 0\n' > "${STUBS}/${p}"
done
printf '#!/bin/bash\necho "no network in tests" >&2\nexit 4\n' > "${STUBS}/wget"
cp "${STUBS}/wget" "${STUBS}/curl"
printf '#!/bin/bash\nwhile [[ "${1:-}" == -* ]]; do shift; done\nexec "$@"\n' > "${STUBS}/sudo"
chmod +x "$STUBS"/*
export PATH="${STUBS}:${PATH}" TERM=dumb HOME="${TMP}/home"
mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL="${TMP}/gitconfig"
printf '[user]\n\tname = ulh test\n\temail = test@example.invalid\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"

# ---------------------------------------------------------------- ulh under test
# upstream = this ulh as a git repository, remote.git = "GitHub", ULH = installed copy
UP="${TMP}/upstream"
mkdir -p "$UP"
if git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
    ( cd "$SRC" && git ls-files -co --exclude-standard -z | xargs -0 cp --parents -t "$UP" 2>/dev/null )
else
    cp -r "$SRC/." "$UP/"
    rm -rf "$UP/apps/cli/data" "$UP/apps/cli/config/repo.yaml" "$UP/apps/cli/config/answer.yaml"
fi
git -C "$UP" init -q
git -C "$UP" add -A
git -C "$UP" commit -qm "ulh under test"
git clone -q --bare "$UP" "${TMP}/remote.git"
ULH="${TMP}/ulh"
git clone -q "${TMP}/remote.git" "$ULH"

case "$(uname -m)" in
    x86_64)        YQ="${ULH}/apps/cli/vendor/yq/yq-amd64" ;;
    aarch64|arm64) YQ="${ULH}/apps/cli/vendor/yq/yq-arm64" ;;
    armv7l)        YQ="${ULH}/apps/cli/vendor/yq/yq-arm" ;;
    *)             YQ="${ULH}/apps/cli/vendor/yq/yq-386" ;;
esac

# ---------------------------------------------------------------- run
for t in "$TESTS"/*.test.sh; do
    echo "$(basename "$t" .test.sh)"
    source "$t"
done

echo ""
echo "passed: ${PASSED}  failed: ${FAILED}"
(( FAILED == 0 ))

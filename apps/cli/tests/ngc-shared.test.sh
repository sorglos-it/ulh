# What holds ACROSS the five NextGenCloud scripts, which no single-script file
# can hold: the one host check that lies in all five as a copy, the rule that no
# pairing or join code ever stands in a message, and the handover of the one
# machine case to ngc-web. Sourced by run.sh.
#
# Why this file is here at all: ngc-api, ngc-controller, ngc-db, ngc-web and
# ngc-all were written on five branches and brought together. Whatever they
# share is now in five places, and a drift in one copy is exactly the fault
# nobody sees. These cases are the bolt against it.

shdir="${TMP}/ngc-shared"
mkdir -p "$shdir"
sdir="${ULH}/apps/cli/assets/scripts"
NGC_SCRIPTS="ngc-all ngc-api ngc-controller ngc-db ngc-web"

# The preparation has to have worked, or everything below measures nothing.
present=0
for s in $NGC_SCRIPTS; do
    [ -f "${sdir}/${s}.sh" ] && present=$((present + 1))
done
check "all five NextGenCloud scripts are here (${present}/5)" test "$present" = 5

# ------------------------------------------- the host check, five times the same
#
# shared/ulh.md, "Hosts und Adressen": a script takes a host only the way
# shared/testdata/ulh/host.sh takes it. Each of the five carries its own copy of
# that check, because an ulh script is one file and shares nothing. So the copies
# have to be the SAME copy: a character class that drifts in one script lets a
# host into a certificate and into api.json that the other four refuse.
for s in $NGC_SCRIPTS; do
    awk '/^valid_host\(\) \{/,/^\}/' "${sdir}/${s}.sh" > "${shdir}/host-${s}.txt"
done
check "valid_host can be read out of ngc-all" \
    grep -q 'grep -Eqx' "${shdir}/host-ngc-all.txt"
drift=0
for s in $NGC_SCRIPTS; do
    cmp -s "${shdir}/host-ngc-all.txt" "${shdir}/host-${s}.txt" || {
        drift=$((drift + 1)); echo "    valid_host of ${s} differs from the one of ngc-all"
    }
done
check "the host check is byte for byte the same in all five scripts" test "$drift" = 0

# And it has to be the check of the contract, not the same wrong one five times.
# These verdicts are the ones host.sh gives, measured against it on 15.10.2026:
# "y" taken, "n" refused.
sh_host() (
    # shellcheck disable=SC1090,SC1091
    source "${ULH}/apps/cli/classes/bootstrap.sh"
    LC_ALL=C
    export LC_ALL
    # shellcheck disable=SC1090
    source "${shdir}/host-${1}.txt"
    valid_host "$2"
)
cat > "${shdir}/hosts.txt" <<'HOSTS'
y|a
y|example.test
y|a-b.c-d.test
y|1.2.3.4
y|0.0.0.0
y|255.255.255.255
y|127.0.0.1
n|A
n|EXAMPLE.test
n|256.1.1.1
n|1.2.3
n|x.1
n|1.2.3.4.5
n|-foo
n|foo-
n|foo..bar
n|.foo
n|foo.
n|foo_bar
n|foo bar
n|::1
n|fe80::1
n|-
n|
HOSTS
wrong=0
hostcases=0
while IFS='|' read -r want host; do
    [ -n "$want" ] || continue
    hostcases=$((hostcases + 1))
    for s in $NGC_SCRIPTS; do
        if sh_host "$s" "$host"; then got=y; else got=n; fi
        [ "$got" = "$want" ] || {
            wrong=$((wrong + 1))
            echo "    ${s}: host '${host}' is ${got}, the contract says ${want}"
        }
    done
done < "${shdir}/hosts.txt"
check "the host check of the contract, in every script (${hostcases} hosts)" \
    test "$wrong" = 0
# A table that was not read measures nothing, so its length is a case of its own.
check "the table of hosts was read (24 lines)" test "$hostcases" = 24

# ------------------------------------------- no code ever stands in a message
#
# shared/ulh.md: a pairing code pairs a server and a join code joins an API, and
# both are good exactly once. Whatever a log_* line prints lands in the terminal
# of the admin, in the scroll of whoever watched, and in whatever they paste into
# an issue. ngc-controller and ngc-all never printed the code itself; ngc-api did
# ("This is no join code: '<the code>'"), and that one line is the reason this
# case exists. Names and reasons belong in a message, values do not.
leaks=0
for s in $NGC_SCRIPTS; do
    hits="$(grep -nE 'log_(error|warn|info)[^#]*\$\{?NGC_(PAIR_CODE|JOIN_CODE)' \
        "${sdir}/${s}.sh" || true)"
    [ -z "$hits" ] || { leaks=$((leaks + 1)); echo "    ${s} prints a code: ${hits}"; }
done
check "no script puts a pairing or join code into a message" test "$leaks" = 0

# The same for the two things that are worth as much: the setup code of the first
# admin and a password out of the answers. The setup code IS printed on purpose,
# once, by ngc-api and ngc-all - but with printf to the terminal, never through
# log_*, which is the line that can end up in a file.
#
# WHAT THIS PATTERN LOOKS FOR, and why it is written this way: an EXPANSION of
# one of those names inside a log_* line, so a $ has to stand in front of the
# name. The first spelling of this case matched the bare name and then threw
# away every line carrying the words "is in no log" - which is exactly the
# wording of the one harmless line in ngc-all, and also of the mutant that puts
# the code INTO that same line. The case was hollow where it mattered, and a
# mutation measured on 15.10.2026 walked straight through it. The prose of a
# warning may name the setup code; only its value may not be there.
logged=0
for s in $NGC_SCRIPTS; do
    hits="$(grep -nE 'log_(error|warn|info)[^#]*\$[({]?[A-Za-z_{(]*(SETUP_CODE|NGC_PASSWORD|NGC_DB_PASSWORD|NGC_MIGRATE_PASSWORD|NGC_PASSWORD_NGC|NGC_PASSWORD_MIGRATE)' \
        "${sdir}/${s}.sh" || true)"
    [ -z "$hits" ] || { logged=$((logged + 1)); echo "    ${s} logs a secret: ${hits}"; }
done
check "no script logs the setup code or a password" test "$logged" = 0

# ------------------------------------------- the one machine case is continuous
#
# This is the point of the whole category. shared/ulh.md gives ngc-all the answer
# cert_mode and says its web.json gets the local API by itself - ngc-all does NOT
# do that half: it writes no web.json and asks no cert_mode, because a second
# virtual host, certificate and balancer in ulh would be a second place to keep
# right (the reason stands at the top of ngc-all.sh). So on one machine nobody
# can sign in until ngc-web has run as well, and the ONLY thing that carries an
# admin from the one script to the other is the last message of ngc-all: the
# address of this API and the fingerprint ngc-web asks for. If that message
# loses either of them, the small installation is a dead end, and no other case
# in this suite would go red.
alldir2="${TMP}/ngc-shared-all"
mkdir -p "$alldir2"
awk 'f && /^case "\$ACTION" in$/ {exit} /^parse_parameters / {f=1; next} f' \
    "${sdir}/ngc-all.sh" > "${alldir2}/body.sh"
check "the body of ngc-all can be read out of it" \
    grep -q '^show_next_steps() {' "${alldir2}/body.sh"

# The certificate and the fingerprint are the API's work and need a running
# machine, so both are stubbed - and the stub is NAMED, as a stub that stands in
# for a real step must be: what is measured here is the message, not openssl.
# Nothing here says the API really makes that certificate.
PIN_STUB="cGluLW9mLXRoZS1hcGktb24tdGhpcy1tYWNoaW5lLTAwMA"
all_next() (
    # shellcheck disable=SC1090,SC1091
    source "${ULH}/apps/cli/classes/bootstrap.sh"
    # shellcheck disable=SC1090
    source "${alldir2}/body.sh"
    NGC_HOSTNAME="ngc.example.org"
    NGC_SETUP_CODE="${alldir2}/setup-code"
    printf 'setup-code-of-the-first-admin\n' > "$NGC_SETUP_CODE"
    wait_for_cert() { return 0; }
    pin_of_cert() { printf '%s\n' "$PIN_STUB"; }
    paired() { return 1; }
    show_next_steps 2>&1
)
all_next > "${alldir2}/next.txt"
check "the last message of ngc-all comes out at all" test -s "${alldir2}/next.txt"
check "it names ngc-web as the next step" grep -q 'ngc-web' "${alldir2}/next.txt"
check "it gives the address of this API, port and all" \
    grep -q 'https://ngc.example.org:7443' "${alldir2}/next.txt"
check "it gives the fingerprint ngc-web asks for" \
    grep -qF "$PIN_STUB" "${alldir2}/next.txt"
check "it says the setup code is for the first admin account" \
    grep -q 'setup-code-of-the-first-admin' "${alldir2}/next.txt"
check "it says the controller is not paired yet" \
    grep -q 'not paired yet' "${alldir2}/next.txt"

# Without a certificate there is no fingerprint, and then the message must NOT
# invent one: it says the API has not made it yet. An empty fingerprint would be
# typed into the web server's configuration by whoever read it.
all_next_nocert() (
    # shellcheck disable=SC1090,SC1091
    source "${ULH}/apps/cli/classes/bootstrap.sh"
    # shellcheck disable=SC1090
    source "${alldir2}/body.sh"
    NGC_HOSTNAME="ngc.example.org"
    NGC_SETUP_CODE="${alldir2}/none"
    wait_for_cert() { return 1; }
    pin_of_cert() { printf 'this-must-never-be-printed\n'; }
    paired() { return 1; }
    show_next_steps 2>&1
)
all_next_nocert > "${alldir2}/nocert.txt"
check "without a certificate it names no fingerprint" \
    not grep -q 'this-must-never-be-printed' "${alldir2}/nocert.txt"
check "without a certificate it says the API has not made it yet" \
    grep -q 'has not made its certificate' "${alldir2}/nocert.txt"

# ------------------------------------------- no script turns a check off
#
# shared/ulh.md, "TLS intern, nie ungeprueft": no script and no program switches
# a certificate check off. This is the one rule a convenient line breaks in
# passing, and it is cheap to hold.
off=0
for s in $NGC_SCRIPTS; do
    hits="$(grep -nE 'SSLProxyVerify +none|--no-check-certificate|--insecure|verify=(false|none)|SSLVerifyClient +none' \
        "${sdir}/${s}.sh" || true)"
    [ -z "$hits" ] || { off=$((off + 1)); echo "    ${s}: ${hits}"; }
done
check "no script switches a certificate check off" test "$off" = 0

# Every one of them sets LC_ALL=C, and above the host check: in another locale
# [a-z] and grep's classes take further letters, and a host nobody wanted ends up
# in a certificate (shared/ulh.md, "Hosts und Adressen").
nolc=0
for s in $NGC_SCRIPTS; do
    lc="$(grep -n '^LC_ALL=C$' "${sdir}/${s}.sh" | head -1 | cut -d: -f1)"
    vh="$(grep -n '^valid_host() {' "${sdir}/${s}.sh" | head -1 | cut -d: -f1)"
    if [ -z "$lc" ] || [ -z "$vh" ] || [ "$lc" -ge "$vh" ]; then
        nolc=$((nolc + 1))
        echo "    ${s}: LC_ALL=C at '${lc:-nowhere}', valid_host at '${vh:-nowhere}'"
    fi
done
check "every script sets LC_ALL=C above its host check" test "$nolc" = 0

unset -f sh_host all_next all_next_nocert
unset shdir sdir NGC_SCRIPTS present drift wrong hostcases leaks logged off nolc
unset alldir2 PIN_STUB

# ngc-controller: what can be checked without a server - the controller.json
# and the service file it writes, byte for byte, which names, addresses, roles,
# passwords and pairing codes it refuses, and that a change of the roles leaves
# the keys of the server alone. Sourced by run.sh.
#
# The functions come out of the script itself, so this tests the file that
# ships and not a copy of it. Each call happens in a subshell, so none of
# ngc-controller's functions stays behind in the test shell.

ctldir="${TMP}/ngc-controller"
mkdir -p "$ctldir"
awk 'f && /^case "\$ACTION" in$/ {exit} /^parse_parameters / {f=1; next} f' \
    "${ULH}/apps/cli/assets/scripts/ngc-controller.sh" > "${ctldir}/body.sh"
check "the functions of ngc-controller can be read out of it" \
    grep -q '^render_controller_json() {' "${ctldir}/body.sh"

# ctl_load is the preamble of every call below: bootstrap for the log_*
# helpers, then the body of the script. LC_ALL=C comes with the body, as it
# does in the script itself.
ctl_load() {
    # shellcheck disable=SC1090,SC1091
    source "${ULH}/apps/cli/classes/bootstrap.sh"
    source "${ctldir}/body.sh"
    WORK="${ctldir}/work"
    mkdir -p "$WORK"
}

# The values of shared/testdata/config/controller.json of the NGC repository,
# the file config.LoadController reads in its tests.
NAME="dienste"
DB1="db-1.ngc.test:3306"
DB2="db-2.ngc.test:3306"
K_NOISE="wcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcE"
K_RELEASE="pKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKQ"
K_DB="zMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzA"
PAIR="ngc-pair:eyJhIjoxfQ"

# Two certificates: ca.text is the text controller.json gets, so its line
# breaks are what the escaping is measured on, and ca.pem is a real certificate
# openssl accepts, which is what read_migrate_ca asks for. A text that only
# looks like a certificate gets no further than that check.
cat > "${ctldir}/ca.text" <<'EOF'
-----BEGIN CERTIFICATE-----
MIIBJjCB2aADAgECAgEBMAUGAytlcDAbMRkwFwYDVQQDExBOR0MgREIgQ0EgKFRl
-----END CERTIFICATE-----
EOF
if command -v openssl > /dev/null 2>&1; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -noenc \
        -days 1 -subj "/CN=NGC DB CA (test)" -keyout "${ctldir}/ca.key" \
        -out "${ctldir}/ca.pem" > /dev/null 2>&1
fi
# Without this certificate nothing below says anything about the answers of the
# role db, so it is a check of its own and not a quiet skip.
check "a real CA certificate for the answer cases is here" \
    test -s "${ctldir}/ca.pem"

# ctl_json renders the provisional controller.json of these roles. $1 is the
# roles separated by a space, $2 the password of the migrate account.
ctl_json() (
    ctl_load
    NGC_NAME="$NAME"
    NGC_MIGRATE_NAME=ngc
    NGC_MIGRATE_USER=ngc_migrate
    NGC_MIGRATE_PASSWORD="${2:-s3cret-pass}"
    CA_PEM="$(cat "${ctldir}/ca.text")
"
    MIG_NODES=("$DB1" "$DB2")
    read -r -a ROLES <<< "${1:-services}"
    case " ${1:-services} " in *" db "*) HAS_DB=1 ;; esac
    case " ${1:-services} " in *" web "*) HAS_WEB=1 ;; esac
    render_controller_json "$K_NOISE" "$K_DB" "$K_RELEASE"
)
ctl_unit() (
    ctl_load
    render_unit
)
ctl_text() (
    ctl_load
    json_text "$1"
)
ctl_kept() (
    ctl_load
    NGC_CONF="$1"
    kept_key "$2" "$3"
)
ctl_host() ( ctl_load; valid_host "$1" )
ctl_name() ( ctl_load; valid_name "$1" )
ctl_ident() ( ctl_load; valid_db_ident "$1" )
ctl_hostport() ( ctl_load; valid_host_port "$1" )
ctl_pass() ( ctl_load; valid_pass "$1" )
ctl_code() ( ctl_load; valid_pair_code "$1" )
ctl_key32() ( ctl_load; valid_b64url_32 "$1" )
ctl_key64() ( ctl_load; valid_b64url_64 "$1" )
# ctl_answers runs the whole chain, as install runs it: name, pair code, roles
# and the five answers of the role db.
ctl_answers() (
    ctl_load
    NGC_NAME="$1"
    NGC_PAIR_CODE="$2"
    NGC_ROLES="$3"
    NGC_MIGRATE_NODES="$4"
    NGC_MIGRATE_NAME="$5"
    NGC_MIGRATE_USER="$6"
    NGC_MIGRATE_PASSWORD="$7"
    NGC_MIGRATE_CA="$8"
    read_answers
)
# ctl_change runs the jq edit of change_settings against a file, so what it
# keeps and what it replaces is measured and not read off the program of jq.
ctl_change() (
    ctl_load
    NGC_CONF="$1"
    read -r -a ROLES <<< "$2"
    case " $2 " in *" db "*) HAS_DB=1 ;; esac
    case " $2 " in *" web "*) HAS_WEB=1 ;; esac
    NGC_MIGRATE_NAME=ngc
    NGC_MIGRATE_USER=ngc_migrate
    NGC_MIGRATE_PASSWORD=s3cret-pass
    CA_PEM="$(cat "${ctldir}/ca.text")
"
    MIG_NODES=("$DB1")
    # put_file is what change_settings ends with, and it wants root and a real
    # /etc; only the jq part is measured here, so the file it made is printed.
    jq --argjson roles "$(roles_json)" \
       --argjson migrate "$(migrate_json)" \
       --arg web "$NGC_WEB_JSON" \
       '.roles = $roles
        | if $migrate == null then del(.migrate) else .migrate = $migrate end
        | if ($roles | index("web")) then .webConfig = $web else del(.webConfig) end' \
       < "$NGC_CONF"
)

# ------------------------------------------------------- controller.json
# config.Controller of the NGC repository, in the shape of
# shared/testdata/config/controller.json: strict JSON, no null, and no field
# that is empty - node is left out (only a trust list gives it), and podman is
# left out (config.parseController fills in /usr/bin/podman).
#
# apis and anchor carry the provisional values the pairing replaces. They are
# in this want file on purpose: this is the one file the program reads BEFORE
# it pairs, and if it ever stopped passing config.Controller.Validate, every
# install would stop at "the configuration of this server is missing".
cat > "${ctldir}/conf.want" <<'EOF'
{
  "name": "dienste",
  "noiseKey": "wcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcE",
  "apis": [
    {
      "url": "wss://unpaired.invalid:7443/tunnel",
      "key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "tls": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    }
  ],
  "anchor": {
    "seq": 1,
    "hash": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  },
  "db": "/var/lib/ngc/controller/state.db",
  "dbKey": "zMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzA",
  "releaseKey": "pKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKQ",
  "roles": ["services"]
}
EOF
ctl_json services > "${ctldir}/conf.got"
check "controller.json: byte for byte the form of the contract" \
    cmp -s "${ctldir}/conf.want" "${ctldir}/conf.got"
# These two are what the provisional file is for, and nothing else may be in
# them: an address that resolves nowhere and 32 zero bytes, which no node and
# no version of a trust list has.
check "controller.json: before the pairing the API is unpaired.invalid" \
    grep -q '"url": "wss://unpaired.invalid:7443/tunnel"' "${ctldir}/conf.got"
check "controller.json: no node of its own before a trust list names one" \
    not grep -q '"node"' "${ctldir}/conf.got"
check "controller.json: podman is left out, config fills it in" \
    not grep -q '"podman"' "${ctldir}/conf.got"
check "controller.json: no migrate without the role db" \
    not grep -q '"migrate"' "${ctldir}/conf.got"
check "controller.json: no webConfig without the role web" \
    not grep -q '"webConfig"' "${ctldir}/conf.got"

# The role web adds webConfig, the role db the whole migrate block, and
# config.Controller.Validate refuses each of them without its role.
ctl_json "web services" > "${ctldir}/conf.web"
check "controller.json: the role web brings webConfig" \
    grep -q '"webConfig": "/etc/ngc/web.json"' "${ctldir}/conf.web"
ctl_json "db services" > "${ctldir}/conf.db"
check "controller.json: migrate names the driver mariadb" \
    grep -q '^    "driver": "mariadb",$' "${ctldir}/conf.db"
check "controller.json: migrate carries one line per database node" \
    test "$(grep -c '^      "db-[12]\.ngc\.test:3306"' "${ctldir}/conf.db")" = 2
check "controller.json: migrate carries the account for the schema" \
    grep -q '^    "user": "ngc_migrate",$' "${ctldir}/conf.db"
# The CA block is the one value with line breaks in it, and a raw one would
# make a file no JSON reader takes.
check "controller.json: the CA certificate carries no raw line break" \
    test "$(grep -c '"ca": "-----BEGIN CERTIFICATE-----\\n' "${ctldir}/conf.db")" = 1
ctl_json "web api db services" > "${ctldir}/conf.all"
check "controller.json: four roles are four entries" \
    grep -q '^  "roles": \["web", "api", "db", "services"\],$' "${ctldir}/conf.all"
# A password is a text of the admin's, so this is where a quote or a backslash
# would break the file in two.
check 'controller.json: a quote in the password is escaped' \
    grep -q '"password": "a\\"b"' <(ctl_json "db services" 'a"b')
check 'controller.json: a backslash in the password is escaped' \
    grep -q '"password": "a\\\\b"' <(ctl_json "db services" 'a\b')

# ------------------------------------------------------------------ json_text
check "json_text: a plain text keeps its quotes around it" test "$(ctl_text abc)" = '"abc"'
check "json_text: a line break becomes \\n" test "$(ctl_text "$(printf 'a\nb')")" = '"a\nb"'
check "json_text: a tab is refused" not ctl_text "$(printf 'a\tb')"
check "json_text: a control character is refused" not ctl_text "$(printf 'a\001b')"

# ------------------------------------------------------------------- kept_key
# dbKey is what the data of every app on this server is encrypted with, and
# there is no second copy of it: a second run of install that drew a new one
# would leave every app's data unreadable.
cp "${ctldir}/conf.got" "${ctldir}/conf.json"
check "kept_key finds dbKey in the controller.json the script itself wrote" \
    test "$(ctl_kept "${ctldir}/conf.json" dbKey 86)" = "$K_DB"
check "kept_key finds noiseKey too" \
    test "$(ctl_kept "${ctldir}/conf.json" noiseKey 43)" = "$K_NOISE"
check "kept_key says nothing about a key that is not there" \
    not ctl_kept "${ctldir}/conf.json" secretKey 43
# A value of the wrong length is not a key, however well it reads - and the
# length is the whole difference between dbKey and the other two.
check "kept_key refuses a dbKey read as 32 bytes" \
    not ctl_kept "${ctldir}/conf.json" dbKey 43
sed 's/"dbKey": ".*"/"dbKey": "tooshort"/' "${ctldir}/conf.json" > "${ctldir}/conf.short"
check "kept_key refuses a dbKey that is not 64 bytes" \
    not ctl_kept "${ctldir}/conf.short" dbKey 86
check "kept_key refuses a file that is not there" \
    not ctl_kept "${ctldir}/nothing.json" dbKey 86

# --------------------------------------------------------------- the service
cat > "${ctldir}/unit.want" <<'EOF'
# /etc/systemd/system/ngc-controller.service
# Written by ngc-controller.sh of ulh (install, configure). Never edit by hand.
[Unit]
Description=NextGenCloud Controller
Documentation=https://github.com/sorglos-it/nextgencloud
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/lib/ngc/ngc-controller -config /etc/ngc/controller.json
# A controller that cannot get the migration lock of its own store does
# not start, and the restart is the job of this service file: a few
# seconds, because the lock falls when the other run is finished.
Restart=on-failure
RestartSec=5
# It runs as root: system accounts, encrypted data folders, containers.
User=root
# /run/ngc, where the controller keeps what one run needs.
RuntimeDirectory=ngc
RuntimeDirectoryMode=0700

[Install]
WantedBy=multi-user.target
EOF
ctl_unit > "${ctldir}/unit.got"
check "ngc-controller.service: byte for byte what the script writes" \
    cmp -s "${ctldir}/unit.want" "${ctldir}/unit.got"
check "ngc-controller.service starts the program out of /usr/lib/ngc" \
    grep -q '^ExecStart=/usr/lib/ngc/ngc-controller -config /etc/ngc/controller.json$' "${ctldir}/unit.got"
# docs/vertraege-v1.2.md, point 32: a controller that cannot get the migration
# lock does not start on purpose, and the restart is this file's job. The
# distance is a few seconds, never anywhere near the 900 seconds of the lock -
# the lock falls as soon as the other run is finished.
check "ngc-controller.service restarts after a failure" \
    grep -q '^Restart=on-failure$' "${ctldir}/unit.got"
check "ngc-controller.service waits a few seconds before it tries again" \
    test "$(sed -n 's/^RestartSec=\([0-9]*\)$/\1/p' "${ctldir}/unit.got")" = 5
check "ngc-controller.service waits far less than the 900 seconds of the lock" \
    test "$(sed -n 's/^RestartSec=\([0-9]*\)$/\1/p' "${ctldir}/unit.got")" -lt 60
check "ngc-controller.service keeps the restart out of systemd's start limit" \
    test "$(( 5 * $(sed -n 's/^RestartSec=\([0-9]*\)$/\1/p' "${ctldir}/unit.got") ))" -gt 10

# --------------------------------------------------- hosts, names, addresses
# The same cases as shared/testdata/ulh/host.sh: a name in lower case or an
# IPv4 address, nothing else.
check "host: a name in lower case" ctl_host db-1.example.org
check "host: an IPv4 address" ctl_host 192.168.1.20
check "host: a capital letter is refused" not ctl_host DB-1.example.org
check "host: IPv6 is refused" not ctl_host "2001:db8::1"
check "host: 256.1.1.1 is refused" not ctl_host 256.1.1.1
check "host: a space is refused" not ctl_host "db 1"
check "host: empty is refused" not ctl_host ""

check "server name: dienste" ctl_name dienste
check "server name: a digit first is refused" not ctl_name 1dienste
check "server name: an underscore is refused" not ctl_name ngc_dienste
check "server name: longer than 32 characters is refused" \
    not ctl_name aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

# valid_db_ident is NOT valid_name: the account ngc-db makes is ngc_migrate.
check "database account: ngc_migrate" ctl_ident ngc_migrate
check "database account: a hyphen is refused" not ctl_ident ngc-migrate
check "database account: a digit first is refused" not ctl_ident 1ngc
check "database account: a space is refused" not ctl_ident "ngc migrate"
check "database account: a quote is refused" not ctl_ident 'ngc"x'
check "database account: a backtick is refused" not ctl_ident 'ngc`x'

check "database node: host and port" ctl_hostport "db-1.example.org:3306"
check "database node: without a port is refused" not ctl_hostport "db-1.example.org"
check "database node: port 0 is refused" not ctl_hostport "db-1.example.org:0"
check "database node: port 70000 is refused" not ctl_hostport "db-1.example.org:70000"
check "database node: a parameter behind the port is refused" \
    not ctl_hostport "db-1.example.org:3306?tls=skip-verify"

check "key: 43 characters of base64url" ctl_key32 "$K_RELEASE"
check "key: 42 characters are refused" not ctl_key32 "${K_RELEASE%?}"
check "key: padding is refused" not ctl_key32 "${K_RELEASE%?}="
check "key: a plus sign is refused" not ctl_key32 "${K_RELEASE%?}+"
check "key of the data: 86 characters of base64url" ctl_key64 "$K_DB"
check "key of the data: 43 characters are refused" not ctl_key64 "$K_RELEASE"

check "password: letters, digits and the allowed signs" ctl_pass "s3cret-pass"
check "password: shorter than 8 characters is refused" not ctl_pass "short"
check "password: a comma is refused" not ctl_pass "pass,word,1"
check "password: a quote is refused" not ctl_pass 'pass"word1'
check "password: a space is refused" not ctl_pass "pass word 1"
# config.DB.Validate refuses this one text, so the script may not write it.
check "password: the literal [secret] is refused" not ctl_pass "[secret]"

check "pairing code: ngc-pair: and base64url" ctl_code "$PAIR"
check "pairing code: without the prefix is refused" not ctl_code "eyJhIjoxfQ"
check "pairing code: the join prefix is refused" not ctl_code "ngc-join:eyJhIjoxfQ"
check "pairing code: nothing behind the colon is refused" not ctl_code "ngc-pair:"
check "pairing code: a character outside base64url is refused" not ctl_code "ngc-pair:ey!x"
# The one secret of this setup. A message that named the code it refused would
# put it into the log of ulh, so no caller of valid_pair_code may print it.
check "the pairing code is in no message of this script" \
    not grep -nE 'log_(info|warn|error).*(NGC_PAIR_CODE|\$\{?code)' \
    "${ULH}/apps/cli/assets/scripts/ngc-controller.sh"
check "the pairing code never stands in a command line" \
    grep -qF 'printf '"'"'%s\n'"'"' "$NGC_PAIR_CODE" |' \
    "${ULH}/apps/cli/assets/scripts/ngc-controller.sh"
check "ngc-controller pair is called with no further word behind it" \
    grep -qF '"${NGC_BIN}/ngc-controller" -config "${WORK}/controller.json" pair' \
    "${ULH}/apps/cli/assets/scripts/ngc-controller.sh"

# ---------------------------------------------------------------- read_answers
# The whole chain, as install runs it. The CA file is the one written above, so
# the way through read_migrate_ca is open - without it every case of the role
# db would fail at the same wall and prove nothing.
check "answers: a server with services alone" \
    ctl_answers "$NAME" "$PAIR" "services" "" "" "" "" ""
check "answers: all four roles with the access of the migrations" \
    ctl_answers "$NAME" "$PAIR" "web api db services" "$DB1 $DB2" ngc ngc_migrate \
    "s3cret-pass" "${ctldir}/ca.pem"
check "answers: a server that is paired already needs no code" \
    ctl_answers "$NAME" "" "services" "" "" "" "" ""
check "answers: no role at all is refused" \
    not ctl_answers "$NAME" "$PAIR" "" "" "" "" "" ""
check "answers: an unknown role is refused" \
    not ctl_answers "$NAME" "$PAIR" "storage" "" "" "" "" ""
check "answers: the same role twice is refused" \
    not ctl_answers "$NAME" "$PAIR" "services services" "" "" "" "" ""
check "answers: a name that is no name is refused" \
    not ctl_answers "Dienste" "$PAIR" "services" "" "" "" "" ""
check "answers: a broken pairing code is refused" \
    not ctl_answers "$NAME" "ngc-pair:ey!x" "services" "" "" "" "" ""
# config.Controller.Validate refuses migrate without the role db and the role
# db without migrate, both ways round, so the script refuses both halves here.
check "answers: the role db without the database nodes is refused" \
    not ctl_answers "$NAME" "$PAIR" "db" "" ngc ngc_migrate "s3cret-pass" "${ctldir}/ca.pem"
check "answers: the role db without the CA is refused" \
    not ctl_answers "$NAME" "$PAIR" "db" "$DB1" ngc ngc_migrate "s3cret-pass" ""
check "answers: the access of the migrations without the role db is refused" \
    not ctl_answers "$NAME" "$PAIR" "services" "$DB1" ngc ngc_migrate "s3cret-pass" "${ctldir}/ca.pem"
check "answers: the same database node twice is refused" \
    not ctl_answers "$NAME" "$PAIR" "db" "$DB1 $DB1" ngc ngc_migrate "s3cret-pass" "${ctldir}/ca.pem"
check "answers: a CA file that is not there is refused" \
    not ctl_answers "$NAME" "$PAIR" "db" "$DB1" ngc ngc_migrate "s3cret-pass" "${ctldir}/nothing.pem"
check "answers: a CA file that is no certificate is refused" \
    not ctl_answers "$NAME" "$PAIR" "db" "$DB1" ngc ngc_migrate "s3cret-pass" "${ULH}/README.md"
check "answers: a relative path to the CA is refused" \
    not ctl_answers "$NAME" "$PAIR" "db" "$DB1" ngc ngc_migrate "s3cret-pass" "ca.pem"
check "answers: a password with a comma is refused" \
    not ctl_answers "$NAME" "$PAIR" "db" "$DB1" ngc ngc_migrate "pass,word" "${ctldir}/ca.pem"

# --------------------------------------------------------- changing the roles
# configure without a new pairing code changes the roles in the file that is
# there. What it may never touch is what the pairing owns - name, noiseKey,
# apis, anchor - and above all dbKey, which the data of every app hangs on.
#
# The file it works on is the one the pairing would have left behind, so the
# API and the anchor here are real-looking values and not the provisional ones:
# a case against the provisional file could not tell "kept" from "written
# again".
# change_settings is the one part of this script that needs jq, which
# ngc-controller.sh installs for itself but no test machine has to have. Where
# it is missing, this says so loudly instead of leaving the whole block out:
# the cases below are the ones that hold the key of every app's data.
if ! command -v jq > /dev/null 2>&1; then
    check "NOT MEASURED: jq is here, so the change of the roles really ran" false
    return 0 2> /dev/null || true
fi

jq '.apis[0].url = "wss://api-1.ngc.test:7443/tunnel"
    | .apis[0].key = "oaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaE"
    | .apis[0].tls = "4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eE"
    | .anchor.hash = "q6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6s"' \
   "${ctldir}/conf.got" > "${ctldir}/paired.json"
# Intermediate check: this is the file the cases below rest on. Without it they
# would compare a change against something that was never there.
check "the paired controller.json for the change cases is here" \
    test "$(jq -r '.apis[0].url' "${ctldir}/paired.json")" = "wss://api-1.ngc.test:7443/tunnel"

ctl_change "${ctldir}/paired.json" "web db services" > "${ctldir}/changed.json"
check "changing the roles: the result is JSON jq takes" jq -e . "${ctldir}/changed.json"
check "changing the roles: the new roles are in" \
    test "$(jq -r '.roles | join(" ")' "${ctldir}/changed.json")" = "web db services"
check "changing the roles: the key of the data is untouched" \
    test "$(jq -r '.dbKey' "${ctldir}/changed.json")" = "$K_DB"
check "changing the roles: the key of this server is untouched" \
    test "$(jq -r '.noiseKey' "${ctldir}/changed.json")" = "$K_NOISE"
check "changing the roles: the API of the pairing is untouched" \
    test "$(jq -r '.apis[0].url' "${ctldir}/changed.json")" = "wss://api-1.ngc.test:7443/tunnel"
check "changing the roles: the anchor of the pairing is untouched" \
    test "$(jq -r '.anchor.hash' "${ctldir}/changed.json")" = "q6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6s"
check "changing the roles: the name of this server is untouched" \
    test "$(jq -r '.name' "${ctldir}/changed.json")" = "$NAME"
check "changing the roles: the role web brings webConfig" \
    test "$(jq -r '.webConfig' "${ctldir}/changed.json")" = "/etc/ngc/web.json"
check "changing the roles: the role db brings migrate" \
    test "$(jq -r '.migrate.user' "${ctldir}/changed.json")" = ngc_migrate
# And the way back: taking the two roles away has to take their two fields with
# them, or config.Controller.Validate refuses the file.
ctl_change "${ctldir}/changed.json" "services" > "${ctldir}/back.json"
check "taking the role web away takes webConfig with it" \
    test "$(jq -r 'has("webConfig")' "${ctldir}/back.json")" = false
check "taking the role db away takes migrate with it" \
    test "$(jq -r 'has("migrate")' "${ctldir}/back.json")" = false
check "taking the roles away leaves the key of the data alone" \
    test "$(jq -r '.dbKey' "${ctldir}/back.json")" = "$K_DB"

# ------------------------------------------------- the mode of the anchor
# /etc/ngc/trust-anchor.json is PUBLIC: index.php of ngc-web reads it and puts
# its number and hash into the config.json of every browser, and Apache runs
# as www-data. With 0600 the interface answered 500 to every call after a
# pairing - measured on Debian 13 on 17.10.2026 (point 61 of the contract
# list). What protects the anchor is the signature of the trust list, not the
# mode of the file, so pair_controller has to leave it 0644. The whole function
# runs here, with its own folders: the only stand-ins are ngc-controller, which
# writes what the pairing would write, and chown, because this suite is not
# root.
pairdir="${ctldir}/pair"
rm -rf "$pairdir"; mkdir -p "${pairdir}/etc" "${pairdir}/bin" "${pairdir}/work" "${pairdir}/state"
cat > "${pairdir}/bin/ngc-controller" <<'STUB'
#!/bin/bash
# What the real pairing leaves behind: a configuration that names an API and
# the anchor next to it. 0600 on purpose - that was the bug.
cat > "${NGC_T_WORK}/controller.json" <<JSON
{"name":"ngc","apis":[{"url":"wss://ngc.ngc.test:7443/tunnel"}]}
JSON
printf '{"seq":1,"hash":"q6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6s"}\n' > "${NGC_T_ANCHOR}"
chmod 0600 "${NGC_T_ANCHOR}"
exit 0
STUB
cat > "${pairdir}/bin/chown" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${NGC_CHOWN_LOG:-/dev/null}"
exit 0
STUB
chmod +x "${pairdir}/bin/ngc-controller" "${pairdir}/bin/chown"
ctl_pair_run() (
    ctl_load
    export PATH="${pairdir}/bin:${PATH}" NGC_CHOWN_LOG="${pairdir}/chown.log"
    WORK="${pairdir}/work"
    NGC_ETC="${pairdir}/etc"
    NGC_CONF="${pairdir}/etc/controller.json"
    NGC_ANCHOR="${pairdir}/etc/trust-anchor.json"
    NGC_BIN="${pairdir}/bin"
    NGC_STATE_DIR="${pairdir}/state"
    NGC_PAIRED="${pairdir}/state/paired"
    NGC_PAIR_CODE="ngc-pair:eyJhIjoxfQ"
    CHANGED=0
    export NGC_T_WORK="$WORK" NGC_T_ANCHOR="$NGC_ANCHOR"
    pair_controller > /dev/null 2>&1
)
: > "${pairdir}/chown.log"
ctl_pair_run
# Intermediate check: the way through pair_controller is open. Without it the
# mode below would be the one of a file the stub wrote and nothing else.
check "pairing (ngc-controller): the configuration of the pairing was taken over" \
    grep -q 'ngc.ngc.test' "${pairdir}/etc/controller.json"
check "pairing (ngc-controller): the anchor is 0644, or the interface answers 500" \
    test "$(stat -c '%a' "${pairdir}/etc/trust-anchor.json")" = 644
check "pairing (ngc-controller): and root:root is asked for it" \
    grep -qE '^root:root -- .*trust-anchor.json$' "${pairdir}/chown.log"
check "pairing (ngc-controller): the configuration itself stays 0600" \
    test "$(stat -c '%a' "${pairdir}/etc/controller.json")" = 600

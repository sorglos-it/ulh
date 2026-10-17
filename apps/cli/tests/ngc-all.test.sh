# ngc-all: what can be checked without a machine - api.json and controller.json
# against an encrypted SQLite file, the two service files, and which names,
# addresses, keys and pairing codes it refuses. Sourced by run.sh.
#
# The functions come out of the script itself, so this tests the file that ships
# and not a copy of it. Each call happens in a subshell, so none of ngc-all's
# functions stays behind in the test shell.

alldir="${TMP}/ngc-all"
mkdir -p "$alldir"
awk 'f && /^case "\$ACTION" in$/ {exit} /^parse_parameters / {f=1; next} f' \
    "${ULH}/apps/cli/assets/scripts/ngc-all.sh" > "${alldir}/body.sh"
check "the functions of ngc-all can be read out of it" grep -q '^render_api_json() {' "${alldir}/body.sh"
check "the functions of the controller side are in there too" \
    grep -q '^render_controller_json() {' "${alldir}/body.sh"

# all_load is the preamble of every call below: bootstrap for the log_* helpers,
# then the body of the script. LC_ALL=C comes with the body, as it does in the
# script itself.
all_load() {
    # shellcheck disable=SC1090,SC1091
    source "${ULH}/apps/cli/classes/bootstrap.sh"
    source "${alldir}/body.sh"
    WORK="${alldir}/work"
    mkdir -p "$WORK"
}

# The values of shared/testdata/config of the NGC repository, so the shapes here
# and the shapes config.LoadAPI and config.LoadController read in their own
# tests are the same ones.
NAME="ngc"
HOST="ngc.ngc.test"
A_NOISE="oaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaE"
A_SIGN="oqKioqKioqKioqKioqKioqKioqKioqKioqKioqKioqI"
A_SECRET="o6Ojo6Ojo6Ojo6Ojo6Ojo6Ojo6Ojo6Ojo6Ojo6Ojo6M"
A_CHALLENGE="pqampqampqampqampqampqampqampqampqampqampqY"
A_RELEASE="pKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKQ"
A_STORE="paWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaU"
# 86 characters: the 64 bytes of AES-256-XTS. Two different ones, because the
# API's file and the controller's file must never share a key either.
DB_KEY="zMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzA"
ST_KEY="3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3Q"

all_api_json() (
    all_load
    NGC_NAME="$NAME"
    TUNNEL_URL="wss://${HOST}:7443/tunnel"
    STORE_URL="https://store.nextgencloud.org"
    STORE_KEY="$A_STORE"
    render_api_json "$A_NOISE" "$A_SIGN" "$A_SECRET" "$A_CHALLENGE" "$A_RELEASE" "${1:-$DB_KEY}"
)
all_ctrl_json() (
    all_load
    NGC_NAME="$NAME"
    render_controller_json "$A_NOISE" "$ST_KEY" "$A_RELEASE" "$DB_KEY"
)
all_unit_api() (
    all_load
    render_unit_api
)
all_unit_ctrl() (
    all_load
    render_unit_ctrl
)
all_text() (
    all_load
    json_text "$1"
)
all_kept() (
    all_load
    kept_key "$1" "$2" "$3"
)
all_kept_db() (
    all_load
    NGC_API_JSON="$1"
    kept_db_key
)
all_host() (
    all_load
    valid_host "$1"
)
all_name() (
    all_load
    valid_name "$1"
)
all_store_url() (
    all_load
    valid_store_url "$1"
)
all_key32() (
    all_load
    valid_b64url_32 "$1"
)
all_key64() (
    all_load
    valid_b64url_64 "$1"
)
all_pair() (
    all_load
    valid_pair_code "$1"
)
all_answers() (
    all_load
    NGC_NAME="$1" NGC_HOSTNAME="$2" NGC_STORE_URL="$3" NGC_STORE_KEY="$4" NGC_PAIR_CODE="$5"
    read_answers > /dev/null 2>&1
)
all_pin() (
    all_load
    pin_of_cert "$1"
)
all_two_files() (
    all_load
    # $1 and $2 are what the two constants are set to for this one call, so the
    # guard is measured and not only read.
    NGC_API_DB="$1" NGC_STATE="$2"
    check_two_files > /dev/null 2>&1
)
all_paths() (
    all_load
    printf '%s %s %s\n' "$NGC_API_DB" "$NGC_STATE" "$UNPAIRED_URL"
)
all_roles() (
    all_load
    printf '%s\n' "${ROLES[*]}"
)

# -------------------------------------------- two programs, two files
# This is what the script is for, so it is the first thing measured: the API and
# the controller never get the same file. On SQLite every program migrates at
# its own start, and the migration lock ngc_lock only holds for the moment of a
# migration - measured on the running programs on 13.10.2026, a second ngc-api
# comes through dbopen.Open and dies at the port.
read -r p_api p_state p_unpaired <<< "$(all_paths)"
check "the API and the controller have two different files" test "$p_api" != "$p_state"
check "the API's file is the one of the contract" test "$p_api" = "/var/lib/ngc/api/ngc.db"
check "the controller's file is the one of the contract" \
    test "$p_state" = "/var/lib/ngc/controller/state.db"
check "the guard lets two different files through" \
    all_two_files /var/lib/ngc/api/ngc.db /var/lib/ngc/controller/state.db
check "the guard refuses one file for both programs" \
    not all_two_files /var/lib/ngc/one.db /var/lib/ngc/one.db
check "this machine carries all four roles" test "$(all_roles)" = "web api db services"

# ------------------------------------------------------------------- api.json
# config.API with config.DB on SQLite: the driver, the file and its 64 byte key,
# and NOTHING else in the db object - config.DB.Validate refuses nodes, name,
# user, password and ca next to a path.
cat > "${alldir}/api.want" <<'EOF'
{
  "node": "ngc",
  "url": "wss://ngc.ngc.test:7443/tunnel",
  "listen": ":7443",
  "cert": "/etc/ngc/tls/api.crt",
  "certKey": "/etc/ngc/tls/api.key",
  "db": {
    "driver": "sqlite",
    "path": "/var/lib/ngc/api/ngc.db",
    "key": "zMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzA"
  },
  "noiseKey": "oaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaE",
  "signKey": "oqKioqKioqKioqKioqKioqKioqKioqKioqKioqKioqI",
  "secretKey": "o6Ojo6Ojo6Ojo6Ojo6Ojo6Ojo6Ojo6Ojo6Ojo6Ojo6M",
  "challengeKey": "pqampqampqampqampqampqampqampqampqampqampqY",
  "releaseKey": "pKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKQ",
  "storeKey": "paWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaU",
  "storeUrl": "https://store.nextgencloud.org"
}
EOF
all_api_json > "${alldir}/api.got"
check "api.json: byte for byte the form of the contract, on SQLite" \
    cmp -s "${alldir}/api.want" "${alldir}/api.got"
check "api.json: the driver is sqlite and not mariadb" \
    grep -q '^    "driver": "sqlite",$' "${alldir}/api.got"
check "api.json: no node of a database server is in it" \
    not grep -q '"nodes"' "${alldir}/api.got"
check "api.json: no account, no password, no CA next to the file" \
    test "$(grep -c '"user"\|"password"\|"ca"' "${alldir}/api.got")" = 0
# 86 characters of base64url are the 64 bytes of AES-256-XTS. 43 would be one
# AES-256 key, which is the wrong cipher for a whole file.
check "api.json: the key of the file is 86 characters, so 64 bytes" \
    test "$(sed -n 's/^    "key": "\([A-Za-z0-9_-]*\)".*$/\1/p' "${alldir}/api.got" | wc -c)" = 87

# ------------------------------------------------------------ controller.json
# config.Controller for this machine: all four roles, webConfig because the role
# web is there (config.Validate refuses one without the other), and migrate on
# the API's SQLite file because the role db is there.
cat > "${alldir}/ctrl.want" <<'EOF'
{
  "name": "ngc",
  "noiseKey": "oaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaE",
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
  "dbKey": "3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3Q",
  "releaseKey": "pKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKQ",
  "roles": ["web", "api", "db", "services"],
  "webConfig": "/etc/ngc/web.json",
  "migrate": {
    "driver": "sqlite",
    "path": "/var/lib/ngc/api/ngc.db",
    "key": "zMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzA"
  }
}
EOF
all_ctrl_json > "${alldir}/ctrl.got"
check "controller.json: byte for byte the form of the contract" \
    cmp -s "${alldir}/ctrl.want" "${alldir}/ctrl.got"
# The provisional file is the whole way this script pairs the controller itself,
# and these three values are what make it harmless: an address that resolves
# nowhere and 32 zero bytes, which no node and no trust list has.
check "the provisional file names the reserved domain .invalid" \
    test "$p_unpaired" = "wss://unpaired.invalid:7443/tunnel"
check "the provisional file carries no real API" \
    grep -q '"url": "wss://unpaired.invalid:7443/tunnel"' "${alldir}/ctrl.got"
check "the provisional file carries 32 zero bytes as the key" \
    grep -q '"key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",' "${alldir}/ctrl.got"
check "the provisional file does NOT name the local API" \
    not grep -q "$HOST" "${alldir}/ctrl.got"
# migrate on one machine is the API's file and the API's key, not an account on
# a database server (shared/ulh.md: auf dem Pi SQLite-Datei und Schluessel).
check "migrate: the driver is sqlite" \
    test "$(grep -c '^    "driver": "sqlite",$' "${alldir}/ctrl.got")" = 1
check "migrate: no account for the schema on a SQLite file" \
    not grep -q 'ngc_migrate' "${alldir}/ctrl.got"
check "migrate: the file is the API's" \
    grep -q '^    "path": "/var/lib/ngc/api/ngc.db",$' "${alldir}/ctrl.got"
check "the controller's own key and the API's key are two different keys" \
    test "$DB_KEY" != "$ST_KEY"

# ---------------------------------------------------------------- the services
cat > "${alldir}/unit-api.want" <<'EOF'
# /etc/systemd/system/ngc-api.service
# Written by ngc-all.sh of ulh (install, configure). Never edit by hand.
[Unit]
Description=NextGenCloud API
Documentation=https://github.com/sorglos-it/nextgencloud
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/lib/ngc/ngc-api -config /etc/ngc/api.json
# On SQLite the API migrates its own file at every start. Whoever does
# not get the migration lock does not start, on purpose - so the
# restart belongs here, and a few seconds is the right distance: the
# lock falls when the other run is finished.
Restart=on-failure
RestartSec=5
# /run/ngc, where the API keeps what one run needs.
RuntimeDirectory=ngc
RuntimeDirectoryMode=0700
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
RestrictNamespaces=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
LockPersonality=yes
MemoryDenyWriteExecute=yes
SystemCallArchitectures=native
ReadWritePaths=/var/lib/ngc /etc/ngc

[Install]
WantedBy=multi-user.target
EOF
all_unit_api > "${alldir}/unit-api.got"
check "ngc-api.service: byte for byte what the script writes" \
    cmp -s "${alldir}/unit-api.want" "${alldir}/unit-api.got"
# The database is a FILE under /var/lib/ngc here, so a read-only system without
# that path would stop the API at its first write.
check "ngc-api.service may write where the database file lies" \
    grep -q '^ReadWritePaths=/var/lib/ngc ' "${alldir}/unit-api.got"

all_unit_ctrl > "${alldir}/unit-ctrl.got"
check "ngc-controller.service starts the program out of /usr/lib/ngc" \
    grep -q '^ExecStart=/usr/lib/ngc/ngc-controller -config /etc/ngc/controller.json$' \
    "${alldir}/unit-ctrl.got"
# Point 32 of the NGC contract: whoever does not get the migration lock at its
# start does not start, and the distance is a few seconds - not the 900 of the
# lock, and not so short that systemd's start limit (5 in 10 s) stops it.
check "ngc-controller.service: Restart=on-failure" \
    grep -qx 'Restart=on-failure' "${alldir}/unit-ctrl.got"
check "ngc-controller.service: RestartSec=5" \
    grep -qx 'RestartSec=5' "${alldir}/unit-ctrl.got"
check "ngc-api.service carries the same restart" \
    test "$(grep -cx 'Restart=on-failure' "${alldir}/unit-api.got")" = 1
# This is the one thing a script can do about two programs on one file: the API
# owns its file, so it starts first and migrates first.
check "ngc-controller.service starts after the API" \
    grep -qx 'After=network-online.target ngc-api.service' "${alldir}/unit-ctrl.got"
# Deliberately NOT a dependency: a controller that stops with the API would be
# worse than one that keeps its tunnels.
check "ngc-controller.service does not require the API" \
    not grep -q '^\(Requires\|BindsTo\|Wants\)=.*ngc-api' "${alldir}/unit-ctrl.got"
check "ngc-controller.service says it runs as root" \
    grep -qx 'User=root' "${alldir}/unit-ctrl.got"
# The controller makes system accounts, mounts encrypted folders and starts
# containers; a sandbox with holes for all three would say sandbox and mean
# nothing.
check "ngc-controller.service claims no sandbox it cannot keep" \
    test "$(grep -c 'ProtectSystem\|NoNewPrivileges\|RestrictNamespaces' "${alldir}/unit-ctrl.got")" = 0

# ------------------------------------------------------------------ json_text
check "json_text: a plain text keeps its quotes around it" test "$(all_text abc)" = '"abc"'
check "json_text: a line break becomes \\n" test "$(all_text "$(printf 'a\nb')")" = '"a\nb"'
check "json_text: a tab is refused" not all_text "$(printf 'a\tb')"
check "json_text: a control character is refused" not all_text "$(printf 'a\001b')"

# -------------------------------------------------------- kept_key, kept_db_key
# A second run must find the keys that are there. On ONE machine that matters
# more than anywhere else: there is no second API and no second copy of any key,
# so a fresh one leaves the whole installation unreadable.
all_api_json > "${alldir}/api.json"
check "kept_key finds noiseKey in the api.json the script itself wrote" \
    test "$(all_kept "${alldir}/api.json" noiseKey 43)" = "$A_NOISE"
check "kept_key finds the last key of the file too" \
    test "$(all_kept "${alldir}/api.json" storeKey 43)" = "$A_STORE"
check "kept_key refuses a key of the wrong length" \
    not all_kept "${alldir}/api.json" noiseKey 86
check "kept_key refuses a file that is not there" \
    not all_kept "${alldir}/nothing.json" noiseKey 43
# The key of the file does not stand at the top level, so it has a reader of its
# own - and that reader is what tells a 64 byte key from a 32 byte one.
check "kept_db_key finds the 64 byte key inside the db object" \
    test "$(all_kept_db "${alldir}/api.json")" = "$DB_KEY"
check "kept_db_key says nothing about a file that is not there" \
    not all_kept_db "${alldir}/nothing.json"
# A 43 character key in that place is one AES-256 key, and AES-256-XTS needs
# two: taking it would be opening the file with half a key.
all_api_json "$A_NOISE" > "${alldir}/api.short"
check "kept_db_key refuses a key of 32 bytes where 64 belong" \
    not all_kept_db "${alldir}/api.short"
check "kept_key does not find the key of the file, which is not at the top level" \
    not all_kept "${alldir}/api.json" key 86

# --------------------------------------------------- hosts, names, keys, codes
check "host: a name in lower case" all_host ngc.example.org
check "host: an IPv4 address" all_host 192.168.1.20
check "host: a capital letter is refused" not all_host NGC.example.org
check "host: IPv6 is refused" not all_host "2001:db8::1"
check "host: 256.1.1.1 is refused" not all_host 256.1.1.1
check "host: empty is refused" not all_host ""

check "name: ngc" all_name ngc
check "name: a digit first is refused" not all_name 1ngc
check "name: an underscore is refused" not all_name ngc_1
check "name: longer than 32 characters is refused" \
    not all_name aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

check "store: https with a name" all_store_url "https://store.example.org"
check "store: http is refused" not all_store_url "http://store.example.org"
check "store: a slash at the end is refused" not all_store_url "https://store.example.org/"
check "store: a path of two dots is refused" not all_store_url "https://store.example.org/../etc"

check "key: 43 characters are 32 bytes" all_key32 "$A_STORE"
check "key: 86 characters are 64 bytes" all_key64 "$DB_KEY"
check "key: 43 characters are not 64 bytes" not all_key64 "$A_STORE"
check "key: 86 characters are not 32 bytes" not all_key32 "$DB_KEY"
check "key: padding is refused" not all_key64 "${DB_KEY%?}="

check "pairing code: ngc-pair: and base64url" all_pair "ngc-pair:eyJhIjoxfQ"
check "pairing code: without the prefix is refused" not all_pair "eyJhIjoxfQ"
check "pairing code: a join code is refused" not all_pair "ngc-join:eyJhIjoxfQ"
check "pairing code: nothing behind the colon is refused" not all_pair "ngc-pair:"
check "pairing code: a character outside base64url is refused" not all_pair "ngc-pair:ey!x"

# ---------------------------------------------------------------- read_answers
# The whole chain, as install runs it. No database answer is in it at all: the
# file and its key are the script's.
check "answers: the ones of the contract are taken" all_answers "$NAME" "$HOST" "" "" ""
check "answers: a store of its own, with address and key" \
    all_answers "$NAME" "$HOST" "https://store.example.org" "$A_STORE" ""
check "answers: a pairing code is taken" \
    all_answers "$NAME" "$HOST" "" "" "ngc-pair:eyJhIjoxfQ"
check "answers: no name is refused" not all_answers "" "$HOST" "" "" ""
check "answers: no address is refused" not all_answers "$NAME" "" "" "" ""
check "answers: a store address without its key is refused" \
    not all_answers "$NAME" "$HOST" "https://store.example.org" "" ""
check "answers: a store key without its address is refused" \
    not all_answers "$NAME" "$HOST" "" "$A_STORE" ""
check "answers: a join code in place of a pairing code is refused" \
    not all_answers "$NAME" "$HOST" "" "" "ngc-join:eyJhIjoxfQ"
check "answers: a broken pairing code is refused" \
    not all_answers "$NAME" "$HOST" "" "" "ngc-pair:ey!x"

# ------------------------------------------------------------- the fingerprint
# pin_of_cert is what ngc-web checks this API by (shared/ulh.md): a wrong
# fingerprint or one computed out of nothing must never come back with 0.
if command -v openssl > /dev/null 2>&1; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -noenc \
        -days 1 -subj "/CN=${HOST}" -keyout "${alldir}/t.key" -out "${alldir}/t.crt" \
        > /dev/null 2>&1
    pin="$(all_pin "${alldir}/t.crt")"
    check "pin: 43 characters out of base64url" all_key32 "$pin"
    check "pin: the same certificate gives the same fingerprint" \
        test "$(all_pin "${alldir}/t.crt")" = "$pin"
    : > "${alldir}/empty.crt"
    check "pin: an empty file gives no fingerprint" not all_pin "${alldir}/empty.crt"
    check "pin: a file that is not there gives no fingerprint" not all_pin "${alldir}/nothing.crt"
    printf 'not a certificate\n' > "${alldir}/junk.crt"
    check "pin: junk gives no fingerprint" not all_pin "${alldir}/junk.crt"
else
    check "openssl is here, so the fingerprint was really computed" false
fi

# ------------------------------------------------------------- change_settings
# This one needs jq, and there is none on the machine this was written on. A
# case that cannot run says so OUT LOUD and is red - a case that skips itself
# over a missing tool is the worst kind of green.
if command -v jq > /dev/null 2>&1; then
    # A chown this suite cannot do: it runs as a normal user, so the
    # "chown root:root" that put_file ends with fails and turns the whole of
    # change_settings into a log_error - the three cases below then measured
    # the missing root and nothing else (red until 15.10.2026). The stub writes
    # down what it was asked for, so the owner stays MEASURED, out of the
    # record instead of out of the file system. Nothing else is stubbed: jq,
    # chmod, mv and cmp all run for real.
    allbin="${alldir}/bin"
    mkdir -p "$allbin"
    cat > "${allbin}/chown" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${NGC_CHOWN_LOG:-/dev/null}"
exit 0
STUB
    chmod +x "${allbin}/chown"
    all_change() (
        all_load
        export PATH="${allbin}:${PATH}" NGC_CHOWN_LOG="${alldir}/chown.log"
        NGC_API_JSON="${alldir}/api.json"
        NGC_CONF="${alldir}/ctrl.change.json"
        cp "${alldir}/ctrl.got" "$NGC_CONF"
        CHANGED_CTRL=0
        change_settings > /dev/null 2>&1
        cat "$NGC_CONF"
    )
    : > "${alldir}/chown.log"
    all_change > "${alldir}/changed.got"
    # Intermediate check: the way through put_file is open. Without it every
    # case below could be comparing against the file that was copied in.
    check "change_settings got as far as writing the file" \
        test "$(wc -c < "${alldir}/changed.got")" -gt 100
    check "change_settings keeps the four roles" \
        grep -q '"web"' "${alldir}/changed.got"
    check "change_settings keeps the key of the pairing" \
        grep -q "$A_NOISE" "${alldir}/changed.got"
    check "change_settings writes migrate on the API's file" \
        grep -q '/var/lib/ngc/api/ngc.db' "${alldir}/changed.got"
    check "change_settings asks for root:root on the file it wrote" \
        grep -qE '^root:root -- ' "${alldir}/chown.log"
    # jq really read it again: a file change_settings left half written would
    # pass every grep above.
    check "change_settings leaves JSON jq takes" jq -e . "${alldir}/changed.got"
else
    check "NOT MEASURED: jq is here, so change_settings of ngc-all really ran" false
fi

# ---------------------------------------------------------- the trust anchor is public
# /etc/ngc/trust-anchor.json is read by index.php of ngc-web, which hands its
# number and hash to every browser in config.json - and Apache runs that as
# www-data. A mode without the read bit for others makes the interface answer
# 500 to every call after a successful pairing; measured on Debian 13 on
# 17.10.2026, where this one line made a freshly paired machine unreachable.
# What protects the anchor is the signature of the trust list, not the mode.
#
# The check is on the BIT and not on the number, because the reason is the bit:
# 0600 and 0640 are wrong alike, and a later 0664 would be right alike. A check
# on the literal 0644 would pass for 0640 if somebody ever wrote that.
anchor_modes() {
    grep -oE 'chmod [0-7]{4} -- "\$NGC_ANCHOR"' "${alldir}/body.sh" | awk '{print $2}'
}
anchor_others_may_read() {
    local modes digit
    modes="$(anchor_modes)"
    # One line and no more: a second chmod would make this reading say nothing.
    [ "$(printf '%s\n' "$modes" | grep -c .)" = 1 ] || return 1
    digit="$(printf '%s' "$modes" | cut -c4)"
    [ "$(( digit & 4 ))" -ne 0 ]
}
check "exactly one chmod decides the mode of the trust anchor" \
    test "$(anchor_modes | grep -c .)" = 1
check "the trust anchor is readable for others, or the interface answers 500 after pairing" \
    anchor_others_may_read

# ------------------------------------------- the service may write where the anchor lies
# /etc/ngc/trust-anchor.json is written by the API itself, not only by this
# script: after it has taken a new version of the trust list in, it moves the
# anchor up. shared/config writeAtomic does that by creating a NEIGHBOUR file
# in the same directory, renaming it over the target and syncing the
# DIRECTORY - so a ReadWritePaths naming the anchor FILE is not enough, it has
# to name the directory.
#
# Measured on Debian 13 on 17.10.2026 with a throwaway unit carrying exactly
# these protections, doing exactly those three steps:
#   ReadWritePaths=/var/lib/ngc /etc/ngc/tls                  mktemp refused, exit 11
#   ReadWritePaths=/var/lib/ngc /etc/ngc/trust-anchor.json    mktemp refused, exit 11
#   ReadWritePaths=/etc/ngc /var/lib/ngc                      written, exit 0
#
# The directory is read OUT OF the script, not written out here: if the anchor
# ever moves, this check moves with it. The byte-for-byte comparison above
# cannot catch this - mutate the template and the expectation together and it
# stays green, which is how the websocket parameter survived.
anchor_dir_of() {
    local anchor
    anchor="$(sed -n 's/^NGC_ANCHOR="\([^"]*\)".*/\1/p' "$1" | head -1)"
    if [ -n "$anchor" ]; then
        printf '%s\n' "${anchor%/*}"
        return 0
    fi
    # ngc-api.sh installs the API alone and never writes the anchor itself, so
    # it carries no NGC_ANCHOR. The anchor is config.AnchorFile and lies in
    # config.Dir, which every one of these scripts carries as NGC_ETC.
    sed -n 's/^NGC_ETC="\([^"]*\)".*/\1/p' "$1" | head -1
}
anchor_dir_writable() {
    local dir rwp p
    dir="$(anchor_dir_of "$1")"
    [ -n "$dir" ] || return 1
    rwp="$(sed -n 's/^ReadWritePaths=//p' "$2" | head -1)"
    [ -n "$rwp" ] || return 1
    for p in $rwp; do
        [ "$p" = "$dir" ] && return 0
    done
    return 1
}
# Without this one an empty reading would make the check below say nothing.
check "the directory of the trust anchor can be read out of the script" \
    test "$(anchor_dir_of "${ULH}/apps/cli/assets/scripts/ngc-all.sh")" = /etc/ngc
check "the service may write in the directory the trust anchor lies in" \
    anchor_dir_writable "${ULH}/apps/cli/assets/scripts/ngc-all.sh" "${alldir}/unit-api.got"

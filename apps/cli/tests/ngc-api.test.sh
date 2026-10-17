# ngc-api: what can be checked without a server - api.json and the service file
# it writes, byte for byte, and which names, addresses, keys, passwords and join
# codes it refuses. Sourced by run.sh.
#
# The functions come out of the script itself, so this tests the file that ships
# and not a copy of it. Each call happens in a subshell, so none of ngc-api's
# functions stays behind in the test shell.

apidir="${TMP}/ngc-api"
mkdir -p "$apidir"
awk 'f && /^case "\$ACTION" in$/ {exit} /^parse_parameters / {f=1; next} f' \
    "${ULH}/apps/cli/assets/scripts/ngc-api.sh" > "${apidir}/body.sh"
check "the functions of ngc-api can be read out of it" grep -q '^render_api_json() {' "${apidir}/body.sh"

# api_load is the preamble of every call below: bootstrap for the log_* helpers,
# then the body of the script. LC_ALL=C comes with the body, as it does in the
# script itself.
api_load() {
    # shellcheck disable=SC1090,SC1091
    source "${ULH}/apps/cli/classes/bootstrap.sh"
    source "${apidir}/body.sh"
    WORK="${apidir}/work"
    mkdir -p "$WORK"
}

# The values of shared/testdata/config/api.json of the NGC repository, the file
# config.LoadAPI reads in its tests.
NODE="api-1"
HOST="api-1.ngc.test"
DB1="db-1.ngc.test:3306"
DB2="db-2.ngc.test:3306"
K_NOISE="oaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaE"
K_SIGN="oqKioqKioqKioqKioqKioqKioqKioqKioqKioqKioqI"
K_SECRET="o6Ojo6Ojo6Ojo6Ojo6Ojo6Ojo6Ojo6Ojo6Ojo6Ojo6M"
K_CHALLENGE="pqampqampqampqampqampqampqampqampqampqampqY"
K_RELEASE="pKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKQ"
K_STORE="paWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaU"

# Two certificates: ca.text is the text api.json gets, so its line breaks are
# what the escaping is measured on, and ca.pem is a real certificate openssl
# accepts, which is what read_db_ca asks for. A text that only looks like a
# certificate gets no further than that check - as the first run of this file
# showed, where every answer case failed at it and the refusals looked right for
# the wrong reason.
cat > "${apidir}/ca.text" <<'EOF'
-----BEGIN CERTIFICATE-----
MIIBJjCB2aADAgECAgEBMAUGAytlcDAbMRkwFwYDVQQDExBOR0MgREIgQ0EgKFRl
-----END CERTIFICATE-----
EOF
if command -v openssl > /dev/null 2>&1; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -noenc \
        -days 1 -subj "/CN=NGC DB CA (test)" -keyout "${apidir}/ca.key" \
        -out "${apidir}/ca.pem" > /dev/null 2>&1
fi
# Without this certificate nothing below says anything about the answers, so it
# is a check of its own and not a quiet skip.
check "a real CA certificate for the answer cases is here" \
    test -s "${apidir}/ca.pem"

api_json() (
    api_load
    NGC_NODE="$NODE"
    TUNNEL_URL="wss://${HOST}:7443/tunnel"
    NGC_DB_NAME=ngc
    NGC_DB_USER=ngc
    NGC_DB_PASSWORD="${1:-s3cret-pass}"
    CA_PEM="$(cat "${apidir}/ca.text")
"
    STORE_URL="https://store.nextgencloud.org"
    STORE_KEY="$K_STORE"
    DB_NODES=("$DB1" "$DB2")
    render_api_json "$K_NOISE" "$K_SIGN" "$K_SECRET" "$K_CHALLENGE" "$K_RELEASE"
)
api_unit() (
    api_load
    render_unit
)
api_text() (
    api_load
    json_text "$1"
)
api_kept() (
    api_load
    NGC_API_JSON="$1"
    kept_key "$2"
)
api_host() (
    api_load
    valid_host "$1"
)
api_name() (
    api_load
    valid_name "$1"
)
api_store_url() (
    api_load
    valid_store_url "$1"
)
api_key32() (
    api_load
    valid_b64url_32 "$1"
)
api_pass() (
    api_load
    valid_pass "$1"
)
api_join() (
    api_load
    valid_join_code "$1"
)
api_hostport() (
    api_load
    valid_host_port "$1"
)
api_answers() (
    api_load
    DB_NODES=()
    NGC_NODE="$1" NGC_HOSTNAME="$2" NGC_DB_DRIVER="$3" NGC_DB_NODES="$4"
    NGC_DB_NAME=ngc NGC_DB_USER=ngc NGC_DB_PASSWORD="$5" NGC_DB_CA="$6"
    NGC_STORE_URL="$7" NGC_STORE_KEY="$8" NGC_JOIN_CODE="$9"
    read_answers > /dev/null 2>&1
)
api_pin() (
    api_load
    pin_of_cert "$1"
)

# ------------------------------------------------------------------- api.json
# config.API of the NGC repository, in the shape and the order of
# shared/testdata/config/api.json: strict JSON, no null, and no field that is
# empty (sessionLifetime and idleTimeout come from config.parseAPI).
cat > "${apidir}/api.want" <<'EOF'
{
  "node": "api-1",
  "url": "wss://api-1.ngc.test:7443/tunnel",
  "listen": ":7443",
  "cert": "/etc/ngc/tls/api.crt",
  "certKey": "/etc/ngc/tls/api.key",
  "db": {
    "driver": "mariadb",
    "nodes": [
      "db-1.ngc.test:3306",
      "db-2.ngc.test:3306"
    ],
    "name": "ngc",
    "user": "ngc",
    "password": "s3cret-pass",
    "ca": "-----BEGIN CERTIFICATE-----\nMIIBJjCB2aADAgECAgEBMAUGAytlcDAbMRkwFwYDVQQDExBOR0MgREIgQ0EgKFRl\n-----END CERTIFICATE-----\n"
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
api_json > "${apidir}/api.got"
check "api.json: byte for byte the form of the contract" \
    cmp -s "${apidir}/api.want" "${apidir}/api.got"
# The CA block is the one value with line breaks in it, and a raw one would make
# a file no JSON reader takes.
check "api.json: the CA certificate carries no raw line break" \
    test "$(grep -c '^    "ca": "-----BEGIN CERTIFICATE-----\\n' "${apidir}/api.got")" = 1
check "api.json: one line per database node" \
    test "$(grep -c '\.ngc\.test:3306"' "${apidir}/api.got")" = 2
# A password is a text of the admin's, so this is where a quote or a backslash
# would break the file in two.
check 'api.json: a quote in the password is escaped' \
    grep -q '"password": "a\\"b"' <(api_json 'a"b')
check 'api.json: a backslash in the password is escaped' \
    grep -q '"password": "a\\\\b"' <(api_json 'a\b')

# ------------------------------------------------------------------ json_text
check "json_text: a plain text keeps its quotes around it" test "$(api_text abc)" = '"abc"'
check "json_text: a line break becomes \\n" test "$(api_text "$(printf 'a\nb')")" = '"a\nb"'
check "json_text: a tab is refused" not api_text "$(printf 'a\tb')"
check "json_text: a control character is refused" not api_text "$(printf 'a\001b')"

# ------------------------------------------------------------------- kept_key
# A second run of install must find the keys that are there: new ones would lock
# the server out of its own installation.
api_json > "${apidir}/api.json"
check "kept_key finds noiseKey in the api.json the script itself wrote" \
    test "$(api_kept "${apidir}/api.json" noiseKey)" = "$K_NOISE"
check "kept_key finds the last key of the file too" \
    test "$(api_kept "${apidir}/api.json" storeKey)" = "$K_STORE"
check "kept_key says nothing about a key that is not there" \
    not api_kept "${apidir}/api.json" dbKey
# A value of the wrong length is not a key, however well it reads.
sed 's/"noiseKey": ".*"/"noiseKey": "tooshort"/' "${apidir}/api.json" > "${apidir}/api.short"
check "kept_key refuses a noiseKey that is not 32 bytes" \
    not api_kept "${apidir}/api.short" noiseKey
check "kept_key refuses a file that is not there" not api_kept "${apidir}/nothing.json" noiseKey

# --------------------------------------------------------------- the service
cat > "${apidir}/unit.want" <<'EOF'
# /etc/systemd/system/ngc-api.service
# Written by ngc-api.sh of ulh (install, configure). Never edit by hand.
[Unit]
Description=NextGenCloud API
Documentation=https://github.com/sorglos-it/nextgencloud
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/lib/ngc/ngc-api -config /etc/ngc/api.json
Restart=on-failure
RestartSec=5
# /run/ngc, which the join writes its answer into.
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
ReadWritePaths=/var/lib/ngc /etc/ngc/tls

[Install]
WantedBy=multi-user.target
EOF
api_unit > "${apidir}/unit.got"
check "ngc-api.service: byte for byte what the script writes" \
    cmp -s "${apidir}/unit.want" "${apidir}/unit.got"
check "ngc-api.service starts the program out of /usr/lib/ngc" \
    grep -q '^ExecStart=/usr/lib/ngc/ngc-api -config /etc/ngc/api.json$' "${apidir}/unit.got"

# --------------------------------------------------- hosts, names, addresses
# The same cases as shared/testdata/ulh/host.sh: a name in lower case or an
# IPv4 address, nothing else.
check "host: a name in lower case" api_host api-1.example.org
check "host: an IPv4 address" api_host 192.168.1.20
check "host: a capital letter is refused" not api_host API-1.example.org
check "host: IPv6 is refused" not api_host "2001:db8::1"
check "host: 256.1.1.1 is refused" not api_host 256.1.1.1
check "host: a space is refused" not api_host "api 1"
check "host: empty is refused" not api_host ""

check "node name: api-1" api_name api-1
check "node name: a digit first is refused" not api_name 1api
check "node name: an underscore is refused" not api_name api_1
check "node name: longer than 32 characters is refused" \
    not api_name aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

check "database node: host and port" api_hostport "db-1.example.org:3306"
check "database node: without a port is refused" not api_hostport "db-1.example.org"
check "database node: port 0 is refused" not api_hostport "db-1.example.org:0"
check "database node: port 70000 is refused" not api_hostport "db-1.example.org:70000"
check "database node: a parameter behind the port is refused" \
    not api_hostport "db-1.example.org:3306?tls=skip-verify"

check "store: https with a name" api_store_url "https://store.example.org"
check "store: https with a port and a path" api_store_url "https://store.example.org:8443/ngc/apps"
check "store: http is refused" not api_store_url "http://store.example.org"
check "store: a slash at the end is refused" not api_store_url "https://store.example.org/"
check "store: two slashes are refused" not api_store_url "https://store.example.org/a//b"
check "store: a path of two dots is refused" not api_store_url "https://store.example.org/../etc"
check "store: a query is refused" not api_store_url "https://store.example.org/a?b=c"

check "key: 43 characters of base64url" api_key32 "$K_STORE"
check "key: 42 characters are refused" not api_key32 "${K_STORE%?}"
check "key: padding is refused" not api_key32 "${K_STORE%?}="
check "key: a plus sign is refused" not api_key32 "${K_STORE%?}+"

check "password: letters, digits and the allowed signs" api_pass "s3cret-pass"
check "password: shorter than 8 characters is refused" not api_pass "short"
check "password: a comma is refused" not api_pass "pass,word,1"
check "password: a quote is refused" not api_pass 'pass"word1'
check "password: a space is refused" not api_pass "pass word 1"
# config.DB.Validate refuses this one text, so the script may not write it.
check "password: the literal [secret] is refused" not api_pass "[secret]"

check "join code: ngc-join: and base64url" api_join "ngc-join:eyJhIjoxfQ"
check "join code: without the prefix is refused" not api_join "eyJhIjoxfQ"
check "join code: a wrong prefix is refused" not api_join "ngc-pair:eyJhIjoxfQ"
check "join code: nothing behind the colon is refused" not api_join "ngc-join:"
check "join code: a character outside base64url is refused" not api_join "ngc-join:ey!x"

# ---------------------------------------------------------------- read_answers
# The whole chain, as install runs it. The CA file is the one written above, so
# the way through read_db_ca is open - without it every case here would fail at
# the same wall and prove nothing.
# Every case that is meant to come THROUGH read_answers names a store of its
# own: while NGC_STORE_KEY_DEFAULT is the placeholder, two empty store answers
# are refused by the bolt measured at the end of this block, and a case with
# them would measure that bolt instead of its own wall.
check "answers: the ones of the contract are taken" \
    api_answers "$NODE" "$HOST" mariadb "$DB1 $DB2" "s3cret-pass" "${apidir}/ca.pem" \
    "https://store.example.org" "$K_STORE" ""
check "answers: a store of its own, with address and key" \
    api_answers "$NODE" "$HOST" mariadb "$DB1" "s3cret-pass" "${apidir}/ca.pem" \
    "https://store.example.org" "$K_STORE" ""
check "answers: a join code is taken" \
    api_answers "$NODE" "$HOST" mariadb "$DB1" "s3cret-pass" "${apidir}/ca.pem" \
    "https://store.example.org" "$K_STORE" "ngc-join:eyJhIjoxfQ"
check "answers: sqlite is refused, that is ngc-all's business" \
    not api_answers "$NODE" "$HOST" sqlite "$DB1" "s3cret-pass" "${apidir}/ca.pem" "" "" ""
check "answers: no database node is refused" \
    not api_answers "$NODE" "$HOST" mariadb "" "s3cret-pass" "${apidir}/ca.pem" "" "" ""
check "answers: the same database node twice is refused" \
    not api_answers "$NODE" "$HOST" mariadb "$DB1 $DB1" "s3cret-pass" "${apidir}/ca.pem" "" "" ""
check "answers: a store address without its key is refused" \
    not api_answers "$NODE" "$HOST" mariadb "$DB1" "s3cret-pass" "${apidir}/ca.pem" \
    "https://store.example.org" "" ""
check "answers: a store key without its address is refused" \
    not api_answers "$NODE" "$HOST" mariadb "$DB1" "s3cret-pass" "${apidir}/ca.pem" "" "$K_STORE" ""
check "answers: a CA file that is not there is refused" \
    not api_answers "$NODE" "$HOST" mariadb "$DB1" "s3cret-pass" "${apidir}/nothing.pem" "" "" ""
check "answers: a CA file that is no certificate is refused" \
    not api_answers "$NODE" "$HOST" mariadb "$DB1" "s3cret-pass" "${ULH}/README.md" "" "" ""
check "answers: a relative path to the CA is refused" \
    not api_answers "$NODE" "$HOST" mariadb "$DB1" "s3cret-pass" "ca.pem" "" "" ""
check "answers: a broken join code is refused" \
    not api_answers "$NODE" "$HOST" mariadb "$DB1" "s3cret-pass" "${apidir}/ca.pem" "" "" "ngc-join:ey!x"

# --------------------------------------------- the bolt of the store key
# The same bolt as in ngc-all (point 56 of the contract list, measured on
# Debian 13 on 16.10.2026): with two empty store answers the placeholder
# reached /etc/ngc/api.json, the API refused the file with "config: invalid
# configuration", and the script reported a running API while the service
# restarted in a loop. The default is read out of the script, so a real store
# key one day turns these cases over instead of leaving them green.
api_answers_out() (
    api_load
    DB_NODES=()
    NGC_NODE="$1" NGC_HOSTNAME="$2" NGC_DB_DRIVER=mariadb NGC_DB_NODES="$3"
    NGC_DB_NAME=ngc NGC_DB_USER=ngc NGC_DB_PASSWORD="s3cret-pass" NGC_DB_CA="$4"
    NGC_STORE_URL="" NGC_STORE_KEY="" NGC_JOIN_CODE=""
    read_answers 2>&1
)
api_store_default() (
    api_load
    printf '%s\n' "$NGC_STORE_KEY_DEFAULT"
)
case "$(api_store_default)" in
*REPLACE-THIS-LINE*)
    check "store: two empty answers are refused while the key is a placeholder" \
        not api_answers "$NODE" "$HOST" mariadb "$DB1" "s3cret-pass" "${apidir}/ca.pem" "" "" ""
    # And it is THIS wall: the CA file and the database node above it are the
    # ones of the cases that pass, so the way down to the bolt is open.
    api_answers_out "$NODE" "$HOST" "$DB1" "${apidir}/ca.pem" > "${apidir}/store.msg" 2>&1
    check "store: and the message names the missing store of NGC" \
        grep -q "NGC has no official app store yet" "${apidir}/store.msg"
    ;;
*)
    check "store: NGC has a real store key now - these cases belong rewritten" false
    ;;
esac

# ------------------------------------------------------------- the fingerprint
# pin_of_cert is what the whole trust between the parts hangs on
# (shared/ulh.md): the web server writes this fingerprint into its
# configuration, so a wrong one or one computed out of nothing must never come
# back with a status of 0.
if command -v openssl > /dev/null 2>&1; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -noenc \
        -days 1 -subj "/CN=${HOST}" -keyout "${apidir}/t.key" -out "${apidir}/t.crt" \
        > /dev/null 2>&1
    pin="$(api_pin "${apidir}/t.crt")"
    check "pin: 43 characters out of base64url" api_key32 "$pin"
    # The same certificate has to give the same fingerprint, and pin.sh of the
    # NGC repository has to give that very one - that part is checked there, by
    # TestTLSPinScript; here it is the shape and the refusals.
    check "pin: the same certificate gives the same fingerprint" \
        test "$(api_pin "${apidir}/t.crt")" = "$pin"
    : > "${apidir}/empty.crt"
    check "pin: an empty file gives no fingerprint" not api_pin "${apidir}/empty.crt"
    check "pin: a file that is not there gives no fingerprint" not api_pin "${apidir}/nothing.crt"
    printf 'not a certificate\n' > "${apidir}/junk.crt"
    check "pin: junk gives no fingerprint" not api_pin "${apidir}/junk.crt"
else
    check "openssl is here, so the fingerprint was really computed" false
fi

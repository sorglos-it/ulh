# ngc-db: what can be checked without a database server - the configuration it
# writes for MariaDB, the OpenSSL configuration for the CA, a real CA with a
# real node certificate made the way install makes them, and which answers it
# refuses. Sourced by run.sh.
#
# The functions come out of the script itself, so this tests the file that ships
# and not a copy of it. Each call happens in a subshell, so none of ngc-db's
# functions stays behind in the test shell.
#
# The lines checked below are the same lines TestGaleraTemplate of the NGC
# repository checks on apps/server-db/templates/galera.cnf. ngc-db carries that
# template as a here-document, because it installs no NGC program files and so
# has no release to take it from: that is a second copy, and this test is what
# keeps the two from drifting apart.

dbdir="${TMP}/ngc-db"
mkdir -p "$dbdir"
awk 'f && /^case "\$ACTION" in$/ {exit} /^parse_parameters / {f=1; next} f' \
    "${ULH}/apps/cli/assets/scripts/ngc-db.sh" > "${dbdir}/body.sh"
check "the functions of ngc-db can be read out of it" grep -q '^render_galera() {' "${dbdir}/body.sh"

# db_load is the preamble of every call below: bootstrap for the log_* helpers,
# then the body of the script.
db_load() {
    # shellcheck disable=SC1090,SC1091
    source "${ULH}/apps/cli/classes/bootstrap.sh"
    source "${dbdir}/body.sh"
    WORK="${dbdir}/work"
    mkdir -p "$WORK"
}

NODE1="db-1.ngc.test:3306"
NODE2="db-2.ngc.test:3306"
NODE3="db-3.ngc.test:3306"
PASS1="Pa55word-ngc"
PASS2="Pa55word-migrate"

db_galera() (
    db_load
    NGC_HOSTNAME="${1:-db-1.ngc.test}"
    NGC_NODES="${NODE1} ${NODE2} ${NODE3}"
    NGC_BOOTSTRAP=no NGC_PASSWORD_NGC="$PASS1" NGC_PASSWORD_MIGRATE="$PASS2"
    NGC_CA_DIR=/etc/ngc/db-ca
    # read_answers, so NODE_NAME and the node list come out of the script and
    # not out of this test: a check that sets them itself proves nothing.
    read_answers > /dev/null 2>&1 || exit 1
    SST_PASS="0123456789abcdef"
    # ${2-...}, not ${2:-...}: ${2:-...} also puts the default in for an EMPTY
    # argument, and the empty list is exactly the case of the very first start.
    render_galera "${2-$(cluster_list)}"
)
db_cacnf() (
    db_load
    render_ca_cnf "$1"
)
db_answers() (
    db_load
    NGC_HOSTNAME="$1" NGC_NODES="$2" NGC_BOOTSTRAP="$3"
    NGC_PASSWORD_NGC="$4" NGC_PASSWORD_MIGRATE="$5" NGC_CA_DIR="$6"
    read_answers > /dev/null 2>&1
)
db_host() (
    db_load
    valid_host "$1"
)
db_cluster() (
    db_load
    NGC_HOSTNAME=db-1.ngc.test NGC_NODES="$*" NGC_BOOTSTRAP=no
    NGC_PASSWORD_NGC="$PASS1" NGC_PASSWORD_MIGRATE="$PASS2" NGC_CA_DIR=/etc/ngc/db-ca
    read_answers > /dev/null 2>&1 || exit 1
    cluster_list
)

# ------------------------------------------------- 60-ngc.cnf: the lines that carry
db_galera > "${dbdir}/galera.got"
cat > "${dbdir}/pinned.txt" <<'EOF'
[mysqld]
[mariabackup]
require_secure_transport=ON
tls_version=TLSv1.3
ssl_ca=/etc/ngc/db-tls/ca.crt
ssl_cert=/etc/ngc/db-tls/node.crt
ssl_key=/etc/ngc/db-tls/node.key
plugin_load_add=file_key_management
file_key_management_encryption_algorithm=AES_CTR
innodb_encrypt_tables=FORCE
innodb_encrypt_log=ON
innodb_encrypt_temporary_tables=ON
encrypt_tmp_disk_tables=ON
encrypt_binlog=ON
aria_encrypt_tables=ON
wsrep_on=ON
binlog_format=ROW
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2
max_allowed_packet=128M
wsrep_sst_method=mariabackup
sql_mode=STRICT_ALL_TABLES,NO_ENGINE_SUBSTITUTION
wsrep_provider=/usr/lib/galera/libgalera_smm.so
wsrep_cluster_name=ngc
file_key_management_filename=/etc/ngc/db-keys/keys.enc
file_key_management_filekey=FILE:/etc/ngc/db-keys/keyfile.key
EOF
missing=0
while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    grep -qxF "$line" "${dbdir}/galera.got" || { missing=$((missing + 1)); echo "    missing: ${line}"; }
done < "${dbdir}/pinned.txt"
check "60-ngc.cnf carries every pinned line of galera.cnf (whole lines)" test "$missing" = 0

# The other way round, and this is what makes "every line" checkable instead of
# a promise: a line the script writes that nobody pins fails the test. The six
# lines skipped here are the ones that carry a value of this node; each has its
# own check further down.
unpinned=0
while IFS= read -r line; do
    case "$line" in
    '' | '#'*) continue ;;
    wsrep_provider_options=* | wsrep_cluster_address=* | wsrep_node_name=* | \
        wsrep_node_address=* | wsrep_sst_auth=* | bind-address=*) continue ;;
    esac
    grep -qxF "$line" "${dbdir}/pinned.txt" ||
        { unpinned=$((unpinned + 1)); echo "    not pinned: ${line}"; }
done < "${dbdir}/galera.got"
check "every other line the script writes is pinned by this test" test "$unpinned" = 0

# The three ssl_* lines above also stand in [mariabackup]. So they are counted
# per section as well: a line only in [mariabackup] would leave the server's own
# TLS off, and a check on the whole text would not see it.
head=0
sed -n '/^\[mysqld\]/,/^\[mariabackup\]/p' "${dbdir}/galera.got" > "${dbdir}/mysqld.part"
for line in ssl_ca=/etc/ngc/db-tls/ca.crt ssl_cert=/etc/ngc/db-tls/node.crt ssl_key=/etc/ngc/db-tls/node.key; do
    grep -qxF "$line" "${dbdir}/mysqld.part" || { head=$((head + 1)); echo "    not in [mysqld]: ${line}"; }
done
check "the three ssl_* lines stand in [mysqld] itself" test "$head" = 0
back=0
sed -n '/^\[mariabackup\]/,$p' "${dbdir}/galera.got" > "${dbdir}/backup.part"
for line in ssl_ca=/etc/ngc/db-tls/ca.crt ssl_cert=/etc/ngc/db-tls/node.crt ssl_key=/etc/ngc/db-tls/node.key; do
    grep -qxF "$line" "${dbdir}/backup.part" || { back=$((back + 1)); echo "    not in [mariabackup]: ${line}"; }
done
check "and in [mariabackup], for the copy to a new node" test "$back" = 0

# The replication is checked against the same CA. One line, so it is grepped as
# a part of it.
prov=0
for part in socket.ssl_ca=/etc/ngc/db-tls/ca.crt socket.ssl_cert=/etc/ngc/db-tls/node.crt \
    socket.ssl_key=/etc/ngc/db-tls/node.key socket.ssl_cipher=TLS_AES_256_GCM_SHA384; do
    grep -qF "$part" "${dbdir}/galera.got" || { prov=$((prov + 1)); echo "    missing: ${part}"; }
done
check "wsrep_provider_options carries the CA, the certificate and TLS 1.3" test "$prov" = 0

forbidden=0
for line in skip-ssl ssl=0 require_secure_transport=OFF wsrep_on=OFF \
    innodb_encrypt_tables=OFF skip-name-resolve=OFF bind-address=0.0.0.0; do
    if grep -qF "$line" "${dbdir}/galera.got"; then
        forbidden=$((forbidden + 1)); echo "    there: ${line}"
    fi
done
check "60-ngc.cnf carries none of the forbidden lines" test "$forbidden" = 0

# No mark of the template may survive: a @...@ left in the file would be a host
# MariaDB cannot read.
check "no @...@ mark is left in the written configuration" \
    not grep -qE '@[A-Z_]+@' "${dbdir}/galera.got"
check "the node is named with its own address" \
    grep -qx 'wsrep_node_address=db-1.ngc.test' "${dbdir}/galera.got"
check "the server listens on its own address only" \
    grep -qx 'bind-address=db-1.ngc.test' "${dbdir}/galera.got"
check "wsrep_node_name is the first label of the host" \
    grep -qx 'wsrep_node_name=db-1' "${dbdir}/galera.got"
check "the cluster address carries every node" \
    grep -qx 'wsrep_cluster_address=gcomm://db-1.ngc.test,db-2.ngc.test,db-3.ngc.test' "${dbdir}/galera.got"
# The very first start of the first node opens the cluster with an empty list.
check "an empty list gives gcomm:// for the very first start" \
    grep -qx 'wsrep_cluster_address=gcomm://' <(db_galera db-1.ngc.test "")
check "the SST password is not left as a mark" \
    grep -qx 'wsrep_sst_auth=sst:0123456789abcdef' "${dbdir}/galera.got"
check "cluster_list takes the hosts out of the node list" \
    test "$(db_cluster "$NODE1" "$NODE2" "$NODE3")" = "db-1.ngc.test,db-2.ngc.test,db-3.ngc.test"

# ------------------------------------------------- db-ca.cnf
db_cacnf db-1.ngc.test > "${dbdir}/ca.got"
check "a name becomes DNS.1" grep -qx 'DNS.1 = db-1.ngc.test' "${dbdir}/ca.got"
check "an IPv4 address becomes IP.1, never DNS" \
    grep -qx 'IP.1 = 192.168.1.10' <(db_cacnf 192.168.1.10)
check "an IPv4 address carries no DNS entry" \
    not grep -q '^DNS' <(db_cacnf 192.168.1.10)
# One @ names a section. Two would look for a section "node_alt@", and the
# certificate would have no subjectAltName at all.
check "subjectAltName names the section with one @" \
    grep -qx 'subjectAltName = @node_alt' "${dbdir}/ca.got"
check "the CA may sign, and only it" grep -q 'CA:TRUE,pathlen:0' "${dbdir}/ca.got"
check "the node certificate may not sign" grep -q 'CA:FALSE' "${dbdir}/ca.got"
check "the node certificate is for a server and a client" \
    grep -qx 'extendedKeyUsage = serverAuth,clientAuth' "${dbdir}/ca.got"
# openssl req reads its options from the section that -section names: without
# these two lines it asks for the name and then stops.
check "ca_dn carries the request options" \
    test "$(sed -n '/^\[ca_dn\]/,/^$/p' "${dbdir}/ca.got" | grep -c '^prompt = no\|^distinguished_name = ')" = 2
check "node_dn carries the request options" \
    test "$(sed -n '/^\[node_dn\]/,/^$/p' "${dbdir}/ca.got" | grep -c '^prompt = no\|^distinguished_name = ')" = 2
check "no @...@ mark is left in the OpenSSL configuration" \
    not grep -qE '@[A-Z_]+@' "${dbdir}/ca.got"

# ------------------------------------------------- openssl really makes it
# Not "the file looks right" but the thing it is for: with this configuration
# openssl has to build a CA and a node certificate that the CA signed and that
# carries the node's name. That is the same sequence install runs.
if command -v openssl > /dev/null 2>&1; then
    o="${dbdir}/ssl"
    mkdir -p "$o"
    db_cacnf db-1.ngc.test > "${o}/db-ca.cnf"
    (
        cd "$o" || exit 1
        openssl genpkey -algorithm ed25519 -out ca.key &&
            openssl req -new -x509 -key ca.key -out ca.crt -days 7300 \
                -config db-ca.cnf -section ca_dn -extensions ca_ext < /dev/null &&
            openssl genpkey -algorithm ed25519 -out node.key &&
            openssl req -new -key node.key -out node.csr -config db-ca.cnf -section node_dn < /dev/null &&
            openssl x509 -req -in node.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
                -out node.crt -days 3650 -extfile db-ca.cnf -extensions node_ext
    ) > "${o}/log" 2>&1
    check "openssl builds the CA and the node certificate with this configuration" test -s "${o}/node.crt"
    check "the CA signed the node certificate" \
        openssl verify -CAfile "${o}/ca.crt" "${o}/node.crt"
    check "the node certificate carries the name of the node" \
        openssl x509 -in "${o}/node.crt" -noout -checkhost db-1.ngc.test
    check "and not the name of another node" \
        not openssl x509 -in "${o}/node.crt" -noout -checkhost db-2.ngc.test
else
    echo "    skipped: openssl is not here, so the certificates were not built"
fi

# ------------------------------------------------- the answers
good=0
while IFS='|' read -r label host nodes boot p1 p2 cadir; do
    [[ -n "$label" ]] || continue
    db_answers "$host" "$nodes" "$boot" "$p1" "$p2" "$cadir" ||
        { good=$((good + 1)); echo "    refused: ${label}"; }
done <<EOF
first of three|db-1.ngc.test|${NODE1} ${NODE2} ${NODE3}|yes|${PASS1}|${PASS2}|/etc/ngc/db-ca
a joining node|db-2.ngc.test|${NODE1} ${NODE2} ${NODE3}|no|${PASS1}|${PASS2}|/etc/ngc/db-ca
one node only|db-1.ngc.test|${NODE1}|yes|${PASS1}|${PASS2}|/etc/ngc/db-ca
an IPv4 address|192.168.1.10|192.168.1.10:3306 192.168.1.11:3306|yes|${PASS1}|${PASS2}|/etc/ngc/db-ca
EOF
check "ngc-db takes the answers that are in order" test "$good" = 0

bad=0
while IFS='|' read -r label host nodes boot p1 p2 cadir; do
    [[ -n "$label" ]] || continue
    if db_answers "$host" "$nodes" "$boot" "$p1" "$p2" "$cadir"; then
        bad=$((bad + 1)); echo "    taken: ${label}"
    fi
done <<EOF
no host||${NODE1}|yes|${PASS1}|${PASS2}|/etc/ngc/db-ca
host in capitals|DB-1.ngc.test|DB-1.ngc.test:3306|yes|${PASS1}|${PASS2}|/etc/ngc/db-ca
host as IPv6|[2001:db8::1]|[2001:db8::1]:3306|yes|${PASS1}|${PASS2}|/etc/ngc/db-ca
this node not in the list|db-9.ngc.test|${NODE1} ${NODE2}|no|${PASS1}|${PASS2}|/etc/ngc/db-ca
no node at all|db-1.ngc.test||yes|${PASS1}|${PASS2}|/etc/ngc/db-ca
node without a port|db-1.ngc.test|db-1.ngc.test|yes|${PASS1}|${PASS2}|/etc/ngc/db-ca
node on port 0|db-1.ngc.test|db-1.ngc.test:0|yes|${PASS1}|${PASS2}|/etc/ngc/db-ca
node on port 99999|db-1.ngc.test|db-1.ngc.test:99999|yes|${PASS1}|${PASS2}|/etc/ngc/db-ca
node with a leading zero in the port|db-1.ngc.test|db-1.ngc.test:03306|yes|${PASS1}|${PASS2}|/etc/ngc/db-ca
the same node twice|db-1.ngc.test|${NODE1} ${NODE1}|yes|${PASS1}|${PASS2}|/etc/ngc/db-ca
bootstrap neither yes nor no|db-1.ngc.test|${NODE1}|maybe|${PASS1}|${PASS2}|/etc/ngc/db-ca
password too short|db-1.ngc.test|${NODE1}|yes|short|${PASS2}|/etc/ngc/db-ca
password with a comma|db-1.ngc.test|${NODE1}|yes|Pa55word,ngc|${PASS2}|/etc/ngc/db-ca
password with a space|db-1.ngc.test|${NODE1}|yes|Pa55word ngc|${PASS2}|/etc/ngc/db-ca
password with a quote|db-1.ngc.test|${NODE1}|yes|Pa55word'ngc|${PASS2}|/etc/ngc/db-ca
password with a semicolon|db-1.ngc.test|${NODE1}|yes|Pa55word;ngc|${PASS2}|/etc/ngc/db-ca
both accounts with the same password|db-1.ngc.test|${NODE1}|yes|${PASS1}|${PASS1}|/etc/ngc/db-ca
no password for ngc_migrate|db-1.ngc.test|${NODE1}|yes|${PASS1}||/etc/ngc/db-ca
CA folder not absolute|db-1.ngc.test|${NODE1}|yes|${PASS1}|${PASS2}|etc/ngc/db-ca
CA folder with ..|db-1.ngc.test|${NODE1}|yes|${PASS1}|${PASS2}|/etc/ngc/../db-ca
CA folder with a space|db-1.ngc.test|${NODE1}|yes|${PASS1}|${PASS2}|/etc/ngc db-ca
EOF
check "ngc-db refuses every answer that is not in order" test "$bad" = 0

# Nothing a shell would read as a command may pass as a host: it would end up in
# MariaDB's configuration and in a certificate.
shell=0
for h in 'a;id' '$(id)' '`id`' 'a b' 'a|b' 'a>b' "a'b" 'a"b' '*' '-a'; do
    if db_host "$h"; then shell=$((shell + 1)); echo "    taken: ${h}"; fi
done
check "ngc-db refuses hosts with shell characters" test "$shell" = 0

# No password and no key may be put on a command line, where every user of the
# machine could read it out of the process list.
# The option itself, not any "-p": "--protocol=socket" holds one and is none.
check "no password goes on a mariadb command line" \
    not grep -qE 'mariadb[^#]*(--password|[[:space:]]-p[^[:space:]])' "${dbdir}/body.sh"
check "the accounts are made from a file, not from -e" \
    grep -q 'mariadb --protocol=socket < "\$sql"' "${dbdir}/body.sh"

# ------------------------------------------------- the folders MariaDB walks through
# MariaDB runs as mysql. The keys and certificates in these two folders belong
# to mysql, so mysql has to get through the folder as well: root:root 0700
# would make every chown below it worthless, and the server would come up
# without TLS or stop at the encryption. 0710 is the way through without a
# listing.
check "db-tls belongs to root:mysql and is 0710" \
    grep -qF 'ensure_dir "$NGC_TLS" root:mysql 0710' "${dbdir}/body.sh"
check "db-keys belongs to root:mysql and is 0710" \
    grep -qF 'ensure_dir "$NGC_KEYS" root:mysql 0710' "${dbdir}/body.sh"
# And the other way round: the private key of the CA is the trust of the whole
# installation, and MariaDB has no business with it.
check "the folder of the CA stays closed to mysql (root:root 0700)" \
    grep -qF 'ensure_dir "$NGC_CA_DIR" root:root 0700' "${dbdir}/body.sh"
check "and it is the only folder left that closed" \
    test "$(grep -c 'ensure_dir .* root:root 0700' "${dbdir}/body.sh")" = 1

# ------------------------------------------------- a key is never open for a moment
# Owner and mode are set before the move, inside WORK, which is 0700 and
# root's. A chmod after the write leaves a window in which the key lies
# readable where it will stay.
check "all four key files go into place through put_secret" \
    test "$(grep -c '^	put_secret ' "${dbdir}/body.sh")" = 4
check "put_secret moves last, after chown and chmod" \
    test "$(sed -n '/^put_secret() {/,/^}/p' "${dbdir}/body.sh" | grep -cE '^	(chown|chmod).*"\$from"')" = 2
check "no key file is chmod-ed after it lies in its place" \
    not grep -qE 'chmod 0400 "\$\{NGC_(KEYS|TLS)\}' "${dbdir}/body.sh"

# ------------------------------------------------- uninstall: warn first, then delete
# A warning after the deletion is a log entry, not a warning.
warn_line="$(grep -n 'cannot be read any more - not by this server' "${dbdir}/body.sh" | head -n1 | cut -d: -f1)"
rm_line="$(grep -n 'rm -rf "\$NGC_TLS"' "${dbdir}/body.sh" | head -n1 | cut -d: -f1)"
check "uninstall warns about the data BEFORE it removes the keys" \
    test -n "$warn_line" -a -n "$rm_line" -a "${warn_line:-0}" -lt "${rm_line:-0}"
# uninstall does not run read_answers, so it checks the one path it deletes.
chk_line="$(sed -n '/^uninstall_ngc_db() {/,/^}/p' "${dbdir}/body.sh" | grep -n 'valid_dir "\$NGC_CA_DIR"' | head -n1 | cut -d: -f1)"
# The command, not the comment above it: "An rm -rf on a path nobody looked
# at" stands two lines earlier and matched first, which made this check red for
# the wrong reason.
del_line="$(sed -n '/^uninstall_ngc_db() {/,/^}/p' "${dbdir}/body.sh" | grep -nE '^	+rm -rf ' | head -n1 | cut -d: -f1)"
check "uninstall checks the folder of the CA before it removes it" \
    test -n "$chk_line" -a -n "$del_line" -a "${chk_line:-0}" -lt "${del_line:-0}"
# The question the human answers has to name the consequence, in every language.
purge_q="$("$YQ" -r '.scripts."ngc-db".actions[] | select(.name == "uninstall") | .prompts[0]
    | [.question, .questionDE, .questionES, .questionIT, .questionFR] | .[]' "${ULH}/apps/cli/assets/catalog.yaml")"
check "the purge question names the data in all five languages" \
    test "$(grep -cE 'read any more|nicht mehr lesbar|no se podr|non saranno|plus lisibles' <<< "$purge_q")" = 5

# ------------------------------------------------- every action says what it needs
check "root is checked for install/configure, sign, uninstall, backup and restore" \
    test "$(grep -c '^	need_root$' "${dbdir}/body.sh")" = 5
check "the distribution is checked for the same five" \
    test "$(grep -c '^	need_debian$' "${dbdir}/body.sh")" = 5

# ================================================================= backup and restore
# These run the two actions for real, with four stubs in their place: the
# server (mariadb, mariadb-dump), the two checks that need a real machine
# (need_root, need_debian) and the question for the passphrase, which needs a
# terminal. Everything that carries the weight is the script's own: the dump
# goes through openssl with the real cipher and the real number of rounds, the
# checksum is a real sha256sum, and what reaches the server is the text the
# script built. So a wrong passphrase, a damaged file and a missing yes are
# measured, not assumed.
#
# db_stub defines the stubs AFTER db_load, so they win over the script's own
# functions of the same name.
db_stub() {
    need_root() { :; }
    need_debian() { :; }
    mariadb_running() { return 0; }
    sleep() { :; }
    # The real one reads the terminal without echo; there is none here. That
    # ask_passphrase reads without echo is checked separately, further down.
    ask_passphrase() {
        BACKUP_PASS_FILE="${WORK}/pass.txt"
        ( umask 077; printf '%s' "$DBPASS" > "$BACKUP_PASS_FILE" )
    }
    mariadb-dump() { cat "${dbdir}/fake-dump.sql"; }
    # restore talks to the server more than once now: it loads, then asks
    # which tables came out, then moves the names. So the stub writes every
    # call and everything it was fed into one transcript, and answers the one
    # question that has an answer - which tables a database holds. The two
    # table lists are files, so a case can say what the server found.
    mariadb() {
        printf '>> mariadb %s\n' "$*" >> "${dbdir}/transcript.txt"
        case "$*" in
        *information_schema*)
            case "$*" in
            *"TABLE_SCHEMA = 'ngc'"*) cat "${dbdir}/tables-ngc.txt" ;;
            *) cat "${dbdir}/tables-fresh.txt" ;;
            esac
            ;;
        *-e*) : ;;
        *) cat >> "${dbdir}/transcript.txt" ;;
        esac
    }
}

# A dump as mariadb-dump writes one: its own first line, a row with a byte
# that only --hex-blob survives, and its own last line.
cat > "${dbdir}/fake-dump.sql" <<'EOF'
-- MariaDB dump 10.19  Distrib 10.11.6-MariaDB, for debian-linux-gnu
--
-- Host: localhost    Database: ngc
DROP TABLE IF EXISTS `ngc_blob`;
CREATE TABLE `ngc_blob` (`id` varbinary(64) NOT NULL, `data` longblob) ENGINE=InnoDB;
INSERT INTO `ngc_blob` VALUES ('1',0x7365637265742d6d61726b6572);
-- Dump completed on 2026-10-10 12:00:00
EOF
# The same dump with its last line cut off: a dump that stopped in the middle.
grep -v '^-- Dump completed' "${dbdir}/fake-dump.sql" > "${dbdir}/short-dump.sql"

# What the server reports after the load, and what it already had. The second
# one matters: restore has to move those aside, not delete them.
printf 'ngc_blob\nngc_user\n' > "${dbdir}/tables-fresh.txt"
printf 'ngc_user\n' > "${dbdir}/tables-ngc.txt"

GOODPASS="correct horse battery staple"
BADPASS="not the passphrase at all"

db_backup() (
    db_load
    db_stub
    DBPASS="$1"
    NGC_BACKUP_DIR="$2"
    backup_ngc_db
)
db_restore() (
    db_load
    db_stub
    DBPASS="$1"
    NGC_BACKUP_FILE="$2"
    NGC_RESTORE_CONFIRM="$3"
    restore_ngc_db
)

store="${dbdir}/store"
mkdir -p "$store"
db_backup "$GOODPASS" "$store" > "${dbdir}/backup.log" 2>&1
backup_code=$?
check "backup runs through and ends with code 0" test "$backup_code" = 0
enc="$(ls "$store"/ngc-*.sql.enc 2>/dev/null | head -n1)"
check "backup leaves the file and its checksum and nothing else" \
    test "$(ls "$store" | wc -l)" = 2
check "the backup file is there" test -n "$enc" -a -s "${enc:-/nonexistent}"
check "its checksum lies beside it" test -s "${enc:-/nonexistent}.sha256"
check "the checksum fits the file" \
    bash -c 'cd "$1" && sha256sum -c --status "$(basename "$2").sha256"' _ "$store" "$enc"
# The whole point of encrypting it: the bytes of the database are not in there.
check "the backup carries no readable dump" \
    not grep -qa 'MariaDB dump' "${enc:-/nonexistent}"
check "the backup carries no readable row" \
    not grep -qa 'ngc_blob' "${enc:-/nonexistent}"
check "openssl can open it again with the passphrase, byte for byte" \
    bash -c 'openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -in "$1" \
        -pass "pass:$2" 2>/dev/null | cmp -s - "$3"' _ "$enc" "$GOODPASS" "${dbdir}/fake-dump.sql"
check "and not with another one" \
    not bash -c 'openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -in "$1" \
        -pass "pass:$2" 2>/dev/null | cmp -s - "$3"' _ "$enc" "$BADPASS" "${dbdir}/fake-dump.sql"
check "the readable dump is gone from the working folder" \
    not test -e "${dbdir}/work/ngc.sql"
check "and so is the passphrase file" not test -e "${dbdir}/work/pass.txt"
# The sentence a human has to read before they put the file away.
check "backup says that without the passphrase nobody opens the file again" \
    grep -q 'nobody opens this file again' "${dbdir}/backup.log"
# It writes one more file every time and removes none. Nothing in ulh cleans
# that folder up, so the human has to be told - a script that may be the last
# thing still working does not delete backups.
check "backup says where the files lie and that nobody tidies them" \
    bash -c 'grep -q "removes none" "$1" && grep -q "${2}" "$1"' _ "${dbdir}/backup.log" "$store"

# A dump without its end mark is not a backup. Measured on the folder: nothing
# may be left there.
empty="${dbdir}/empty-store"
mkdir -p "$empty"
cp "${dbdir}/fake-dump.sql" "${dbdir}/keep-dump.sql"
cp "${dbdir}/short-dump.sql" "${dbdir}/fake-dump.sql"
db_backup "$GOODPASS" "$empty" > "${dbdir}/backup-short.log" 2>&1
check "backup refuses a dump that has no end mark" test "$?" != 0
check "and leaves nothing behind in the folder" test "$(ls "$empty" | wc -l)" = 0
check "it says the server was busy or the dump stopped" \
    grep -q 'the dump carries no end mark' "${dbdir}/backup-short.log"
cp "${dbdir}/keep-dump.sql" "${dbdir}/fake-dump.sql"

# A folder nobody may back up into. Each of these three EXISTS, so only the
# grammar can refuse it: with a folder that is simply not there, "test -d"
# refuses them all, and the check for the grammar would be green with the
# grammar taken out - measured, it was.
mkdir -p "${dbdir}/with space"
check "backup refuses a folder that is not absolute" \
    not db_backup "$GOODPASS" "."
check "backup refuses a folder with .., even one that is there" \
    not db_backup "$GOODPASS" "${store}/../store"
check "backup refuses a folder with a space in its name" \
    not db_backup "$GOODPASS" "${dbdir}/with space"
check "backup refuses a folder that is not there" \
    not db_backup "$GOODPASS" "/var/backups/ngc-does-not-exist"

# ----------------------------------------------------- restore
rm -f "${dbdir}/transcript.txt"
db_restore "$GOODPASS" "$enc" yes > "${dbdir}/restore.log" 2>&1
restore_code=$?
check "restore runs through and ends with code 0" test "$restore_code" = 0
# The whole point of the safer form: ngc itself is NEVER dropped. Between a
# DROP DATABASE ngc and the last statement of the dump, ngc would be neither
# the old state nor the new one, and nothing would bring the old one back.
# The backticks are in the pattern on purpose: the empty database of the load
# IS dropped, and that one is called ngc_restore_<stamp>.
# Both spellings, quoted and not: the first version of this check looked for
# the backticks only, and the form it is here to catch writes
# "DROP DATABASE IF EXISTS ngc;" without them - so it was green against the
# very thing it guards. The pattern ends at the semicolon, so the empty
# database of the load (ngc_restore_<stamp>, which IS dropped) does not match.
check "restore never drops the database ngc" \
    not grep -qiE 'DROP DATABASE( IF EXISTS)? `?ngc`? *;' "${dbdir}/transcript.txt"
check "the dump goes into a database of its own first" \
    grep -qE 'CREATE DATABASE `ngc_restore_[0-9]{14}` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;' "${dbdir}/transcript.txt"
check "and the whole dump really arrives there" \
    grep -q '0x7365637265742d6d61726b6572' "${dbdir}/transcript.txt"
# "The database is called ngc afterwards" would also be green if nothing had
# been loaded. So: the tables the server reported are the tables that are
# moved onto the name, each one of them.
check "every table of the backup is moved onto the name ngc" \
    test "$(grep -oE '`ngc_restore_[0-9]{14}`\.`[a-z_]+` TO `ngc`\.`[a-z_]+`' \
        "${dbdir}/transcript.txt" | wc -l)" = 2
check "the blob table is one of them" \
    grep -qE '`ngc_restore_[0-9]{14}`\.`ngc_blob` TO `ngc`\.`ngc_blob`' "${dbdir}/transcript.txt"
check "restore counted the tables and said how many" \
    grep -q '2 tables came out of the backup' "${dbdir}/restore.log"
# What was in ngc is moved aside, not deleted, and the old table that is NOT
# in the backup has to be among the moved ones.
check "what was in ngc is moved aside into a database of its own" \
    grep -qE 'CREATE DATABASE `ngc_before_[0-9]{14}`' "${dbdir}/transcript.txt"
check "the table that was there is moved aside, not dropped" \
    grep -qE '`ngc`\.`ngc_user` TO `ngc_before_[0-9]{14}`\.`ngc_user`' "${dbdir}/transcript.txt"
check "and the kept database is never dropped by the script" \
    not grep -qE 'DROP DATABASE IF EXISTS `ngc_before_' "${dbdir}/transcript.txt"
check "the empty database of the load is cleaned up" \
    grep -qE 'DROP DATABASE IF EXISTS `ngc_restore_[0-9]{14}`;' "${dbdir}/transcript.txt"
check "restore says where the old data are now" \
    grep -qE 'is in ngc_before_[0-9]{14}, untouched' "${dbdir}/restore.log"
check "and names the one command that removes them, by hand" \
    grep -qE 'DROP DATABASE .*ngc_before_[0-9]{14}' "${dbdir}/restore.log"
check "restore says that the schema still has to be brought up" \
    grep -q 'ngc-api migrate' "${dbdir}/restore.log"
check "restore leaves no readable dump behind" not test -e "${dbdir}/work/ngc.sql"
check "and no passphrase file" not test -e "${dbdir}/work/pass.txt"
# The warning has to say that this is not a local matter.
check "the warning says that every node of the cluster is hit" \
    grep -q 'DOES NOT STOP AT THIS SERVER' "${dbdir}/restore.log"
check "and that the installation needs room for both states" \
    grep -q 'needs room for both' "${dbdir}/restore.log"

# A load that produced no table at all: that is not a backup, and ngc may not
# be touched. "test -d" of a database does not exist, so this is the case that
# tells "the name is there" from "the data are there".
printf '' > "${dbdir}/tables-fresh.txt"
rm -f "${dbdir}/transcript.txt"
db_restore "$GOODPASS" "$enc" yes > "${dbdir}/restore-notables.log" 2>&1
check "restore refuses a backup that loaded without a table" test "$?" != 0
check "and moves no name at all" \
    not grep -q 'RENAME TABLE' "${dbdir}/transcript.txt"
check "it says ngc was not touched" \
    grep -q 'was NOT touched' "${dbdir}/restore-notables.log"
check "and it removes its own half-loaded database" \
    grep -qE 'DROP DATABASE IF EXISTS `ngc_restore_[0-9]{14}`;' "${dbdir}/transcript.txt"

# A table name out of the backup that would end the quoting of the RENAME
# statement. The names come from the file, so they come from outside.
printf 'ngc_blob\nbad`name\n' > "${dbdir}/tables-fresh.txt"
rm -f "${dbdir}/transcript.txt"
db_restore "$GOODPASS" "$enc" yes > "${dbdir}/restore-badtable.log" 2>&1
check "restore refuses a table name it would have to quote" test "$?" != 0
check "and moves no name then either" \
    not grep -q 'RENAME TABLE' "${dbdir}/transcript.txt"
printf 'ngc_blob\nngc_user\n' > "${dbdir}/tables-fresh.txt"

# A dump that names a database of its own would step out of the one this
# script chose and write wherever it likes.
for bad_line in 'CREATE DATABASE `other`;' 'USE other;' \
    'CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v` AS SELECT 1;'; do
    bad_dir="${dbdir}/bad-$(printf '%s' "$bad_line" | cksum | cut -d' ' -f1)"
    mkdir -p "$bad_dir"
    { head -n 3 "${dbdir}/fake-dump.sql"; printf '%s\n' "$bad_line"
      tail -n 4 "${dbdir}/fake-dump.sql"; } > "${dbdir}/bad-dump.sql"
    openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -salt \
        -in "${dbdir}/bad-dump.sql" -out "${bad_dir}/ngc-bad.sql.enc" \
        -pass "pass:${GOODPASS}" 2>/dev/null
    ( cd "$bad_dir" && sha256sum ngc-bad.sql.enc > ngc-bad.sql.enc.sha256 )
    rm -f "${dbdir}/transcript.txt"
    db_restore "$GOODPASS" "${bad_dir}/ngc-bad.sql.enc" yes > /dev/null 2>&1
    check "restore refuses a dump that carries: ${bad_line}" test "$?" != 0
    check "  and does not even start to load it" not test -e "${dbdir}/transcript.txt"
done

# Without the yes nothing happens at all - and "nothing" is measured on the
# server side, not on the exit code.
rm -f "${dbdir}/transcript.txt"
db_restore "$GOODPASS" "$enc" no > "${dbdir}/restore-no.log" 2>&1
check "restore without the yes stops" test "$?" != 0
check "and nothing reached the server" not test -e "${dbdir}/transcript.txt"
check "it warned about the data before it asked" \
    grep -q 'DOES NOT STOP AT THIS SERVER' "${dbdir}/restore-no.log"
rm -f "${dbdir}/transcript.txt"
db_restore "$GOODPASS" "$enc" maybe > /dev/null 2>&1
check "an answer that is neither yes nor no counts as no" not test -e "${dbdir}/transcript.txt"

# A wrong passphrase, a missing checksum, a changed byte: each one stops before
# the database is touched.
rm -f "${dbdir}/transcript.txt"
db_restore "$BADPASS" "$enc" yes > "${dbdir}/restore-badpass.log" 2>&1
check "restore refuses a wrong passphrase" test "$?" != 0
check "and touches nothing" not test -e "${dbdir}/transcript.txt"

cp "$enc" "${dbdir}/lonely.sql.enc"
rm -f "${dbdir}/transcript.txt"
db_restore "$GOODPASS" "${dbdir}/lonely.sql.enc" yes > "${dbdir}/restore-nosum.log" 2>&1
check "restore refuses a backup without its checksum" test "$?" != 0
check "and touches nothing then either" not test -e "${dbdir}/transcript.txt"

broken="${dbdir}/broken"
mkdir -p "$broken"
cp "$enc" "${broken}/ngc-broken.sql.enc"
( cd "$broken" && sha256sum ngc-broken.sql.enc > ngc-broken.sql.enc.sha256 )
# One byte in the middle, far behind the salt: the checksum has to catch it.
printf 'X' | dd of="${broken}/ngc-broken.sql.enc" bs=1 seek=40 conv=notrunc status=none
rm -f "${dbdir}/transcript.txt"
db_restore "$GOODPASS" "${broken}/ngc-broken.sql.enc" yes > "${dbdir}/restore-broken.log" 2>&1
check "restore refuses a file whose checksum does not fit" test "$?" != 0
check "and says so before it asks for the passphrase" \
    grep -q 'checksum does not fit' "${dbdir}/restore-broken.log"
check "and touches nothing" not test -e "${dbdir}/transcript.txt"

# Something that decrypts cleanly and is not a dump of ngc. A passphrase that
# is right says nothing about what is inside.
other="${dbdir}/other"
mkdir -p "$other"
printf 'this is not a dump\n' > "${dbdir}/notadump.txt"
openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -salt \
    -in "${dbdir}/notadump.txt" -out "${other}/ngc-other.sql.enc" -pass "pass:${GOODPASS}" 2>/dev/null
( cd "$other" && sha256sum ngc-other.sql.enc > ngc-other.sql.enc.sha256 )
rm -f "${dbdir}/transcript.txt"
db_restore "$GOODPASS" "${other}/ngc-other.sql.enc" yes > "${dbdir}/restore-other.log" 2>&1
check "restore refuses a file that is not a dump of MariaDB" test "$?" != 0
check "and touches nothing" not test -e "${dbdir}/transcript.txt"

# A dump that stopped in the middle, encrypted and with a fitting checksum:
# only the end mark catches this one.
cut="${dbdir}/cut"
mkdir -p "$cut"
openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -salt \
    -in "${dbdir}/short-dump.sql" -out "${cut}/ngc-cut.sql.enc" -pass "pass:${GOODPASS}" 2>/dev/null
( cd "$cut" && sha256sum ngc-cut.sql.enc > ngc-cut.sql.enc.sha256 )
rm -f "${dbdir}/transcript.txt"
db_restore "$GOODPASS" "${cut}/ngc-cut.sql.enc" yes > "${dbdir}/restore-cut.log" 2>&1
check "restore refuses a dump without its end mark" test "$?" != 0
check "and touches nothing" not test -e "${dbdir}/transcript.txt"

# Again: files that are really there, checksum and all, so only the grammar
# can refuse them.
spaced="${dbdir}/with space"
cp "$enc" "${enc}.sha256" "$spaced/" 2>/dev/null
check "restore refuses a path with .., even one that leads to the file" \
    not db_restore "$GOODPASS" "${store}/../store/$(basename "${enc:-x}")" yes
check "restore refuses a path with a space in it" \
    not db_restore "$GOODPASS" "${spaced}/$(basename "${enc:-x}")" yes

# ----------------------------------------------------- the secrets, read against the code
# The warning has to stand BEFORE the line that loads the dump; after it, it is
# a log entry and no warning. Same shape as the check for uninstall above.
# Counted inside restore_ngc_db, not over the whole body: ensure_database holds
# the very same "mariadb --protocol=socket < " line, it stands further up, and
# grep over the whole body took that one - which made this check red for a
# reason that had nothing to do with restore.
sed -n '/^restore_ngc_db() {/,/^}/p' "${dbdir}/body.sh" > "${dbdir}/restore.part"
r_warn="$(grep -n 'The database ngc will be replaced by this backup' "${dbdir}/restore.part" | head -n1 | cut -d: -f1)"
r_load="$(grep -n 'mariadb --protocol=socket < "\$sql"' "${dbdir}/restore.part" | head -n1 | cut -d: -f1)"
r_tables="$(grep -n 'list_tables "\$fresh"' "${dbdir}/restore.part" | head -n1 | cut -d: -f1)"
check "restore warns about the data BEFORE it loads the dump" \
    test -n "$r_warn" -a -n "$r_load" -a "${r_warn:-0}" -lt "${r_load:-0}"
r_conf="$(grep -n 'NGC_RESTORE_CONFIRM' "${dbdir}/restore.part" | tail -n1 | cut -d: -f1)"
check "and it asks for the yes before that line too" \
    test -n "$r_conf" -a -n "$r_load" -a "${r_conf:-0}" -lt "${r_load:-0}"
# And the table count stands between the load and the rename, not after it:
# counted afterwards it would be a report, not a condition.
# The command, not the comment that explains it: the comment above the code
# says "RENAME TABLE" too, it stands further up, and a plain grep took that
# one - the same trap the check for uninstall above already fell into once.
r_ren="$(grep -nF "printf 'RENAME TABLE'" "${dbdir}/restore.part" | head -n1 | cut -d: -f1)"
check "restore counts the tables after the load and before the rename" \
    test -n "$r_tables" -a -n "$r_ren" -a "${r_load:-0}" -lt "${r_tables:-0}" \
        -a "${r_tables:-0}" -lt "${r_ren:-0}"

# No secret on a command line. "-pass pass:" would put the passphrase in the
# process list of the machine, where every user can read it; "-pass file:" puts
# the path of a 0600 file there.
check "the passphrase goes to openssl as a file, never as pass:" \
    not grep -q 'pass "pass:' "${dbdir}/body.sh"
check "both calls of openssl enc read it out of the file" \
    test "$(grep -c 'pass "file:\${BACKUP_PASS_FILE}"' "${dbdir}/body.sh")" = 2
check "the passphrase is read without echo" \
    grep -q 'read -rs first' "${dbdir}/body.sh"
check "its file is written under umask 077, not chmod-ed afterwards" \
    test "$(sed -n '/^ask_passphrase() {/,/^}/p' "${dbdir}/body.sh" | grep -c 'umask 077')" = 1
check "no chmod ever touches the passphrase file" \
    not grep -q 'chmod.*BACKUP_PASS_FILE' "${dbdir}/body.sh"
# The server is reached over the socket as root, so there is no database
# password in this script at all - the existing check above forbids one on a
# command line, this one forbids the option anywhere.
check "mariadb-dump is called over the socket" \
    grep -q 'mariadb-dump --protocol=socket' "${dbdir}/body.sh"
check "--hex-blob is there: every blob column of NGC is binary" \
    grep -q -- '--hex-blob' "${dbdir}/body.sh"
check "no routine and no event is dumped, so none can run on restore" \
    test "$(grep -c -- '--routines=FALSE --events=FALSE' "${dbdir}/body.sh")" = 1

# The passphrase must not be an answer: an answer travels through the
# environment and through config/answer.yaml.
back_vars="$("$YQ" -r '.scripts."ngc-db".actions[] | select(.name == "backup") | .prompts[].variable' \
    "${ULH}/apps/cli/assets/catalog.yaml")"
check "backup asks for the folder and for nothing else" test "$back_vars" = NGC_BACKUP_DIR
rest_vars="$("$YQ" -r '.scripts."ngc-db".actions[] | select(.name == "restore") | .prompts[].variable' \
    "${ULH}/apps/cli/assets/catalog.yaml")"
check "restore asks for the file and for the yes, and for nothing else" \
    test "$rest_vars" = "NGC_BACKUP_FILE
NGC_RESTORE_CONFIRM"
# Whole names, anchored: NGC_PASSWORD_NGC of install is an answer and has to
# stay one. What may never become an answer is the passphrase of a backup.
check "no answer of ngc-db carries the passphrase of a backup" \
    not grep -qixE 'NGC_BACKUP_(PASS|PASSPHRASE|PASSWORD)|NGC_PASSPHRASE' \
        <("$YQ" -r '.scripts."ngc-db".actions[].prompts[].variable' "${ULH}/apps/cli/assets/catalog.yaml")
# The yes is a yes/no question, so ulh asks it in the admin's language and
# hands the script "yes" or "no" whatever was typed.
check "the confirmation is a yes/no question with the default no" \
    test "$("$YQ" -r '.scripts."ngc-db".actions[] | select(.name == "restore")
        | .prompts[1] | .type + " " + .default' "${ULH}/apps/cli/assets/catalog.yaml")" = "yes/no no"
# And it has to name what is lost, in every language - as the purge question does.
restore_q="$("$YQ" -r '.scripts."ngc-db".actions[] | select(.name == "restore") | .prompts[1]
    | [.question, .questionDE, .questionES, .questionIT, .questionFR] | .[]' "${ULH}/apps/cli/assets/catalog.yaml")"
check "the restore question names the loss in all five languages" \
    test "$(grep -cE 'gone for good|unwiderruflich weg|se perder|perduti per sempre|perdues' <<< "$restore_q")" = 5

unset -f db_stub db_backup db_restore
unset GOODPASS BADPASS store enc empty broken other cut backup_code restore_code
unset r_warn r_load r_conf r_tables r_ren back_vars rest_vars restore_q spaced
unset bad_line bad_dir

unset -f db_load db_galera db_cacnf db_answers db_host db_cluster
unset dbdir NODE1 NODE2 NODE3 PASS1 PASS2 missing unpinned head back prov forbidden good bad shell o
unset warn_line rm_line chk_line del_line purge_q line

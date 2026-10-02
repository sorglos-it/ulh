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
check "root is checked for install/configure, sign and uninstall" \
    test "$(grep -c '^	need_root$' "${dbdir}/body.sh")" = 3
check "the distribution is checked for the same three" \
    test "$(grep -c '^	need_debian$' "${dbdir}/body.sh")" = 3

unset -f db_load db_galera db_cacnf db_answers db_host db_cluster
unset dbdir NODE1 NODE2 NODE3 PASS1 PASS2 missing unpinned head back prov forbidden good bad shell o
unset warn_line rm_line chk_line del_line purge_q line

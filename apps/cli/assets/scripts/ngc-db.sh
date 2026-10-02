#!/bin/bash

# ngc-db - NextGenCloud: MariaDB with Galera, TLS and encryption at rest
# (Debian and Ubuntu).
#
# What it does: MariaDB, Galera and mariabackup from the package sources, the
# encryption keys for file_key_management, the CA of this installation on the
# bootstrap node, a certificate for every node, /etc/mysql/mariadb.conf.d/60-ngc.cnf
# and the accounts ngc, ngc_migrate and sst. At the end it prints the CA
# certificate: it goes into ngc-api as db_ca and into ngc-controller as
# migrate_ca. Contract: shared/ulh.md of the NGC repository
# (github.com/sorglos-it/nextgencloud), and the two templates of
# apps/server-db/templates/ - galera.cnf and db-ca.cnf, which this file carries
# as here-documents because ngc-db installs no NGC program files and so has no
# release to take them from. TestGaleraTemplate of the NGC repository guards the
# copy there, apps/cli/tests/ngc-db.test.sh guards the copy here; a change
# belongs in both.
#
# The prompts of assets/catalog.yaml carry the answers, in this order (ulh joins
# them with commas, so no answer may hold a comma - that is why the node list is
# separated by spaces and a password with a comma is refused). install,
# configure and sign check them all in read_answers before they are used;
# uninstall is asked for NGC_PURGE alone and checks NGC_CA_DIR itself, right
# before it would delete it:
#   1 hostname          NGC_HOSTNAME          name or IPv4 address of THIS node
#   2 nodes             NGC_NODES             <host>:<port> of every node
#   3 bootstrap         NGC_BOOTSTRAP         yes on the first node, else no
#   4 password_ngc      NGC_PASSWORD_NGC      the account that reads and writes
#   5 password_migrate  NGC_PASSWORD_MIGRATE  the account that changes the schema
#   6 ca_dir            NGC_CA_DIR            where the CA key stays, bootstrap only
#
# Everything this script prints is English, as in every other ulh script. The
# five languages of ulh sit in assets/catalog.yaml.
#
# backup and restore are not here yet: they come with task 12 of the database
# plan, together with the pull request.

set -eu
source "$(dirname "$0")/../../classes/bootstrap.sh"
# The script itself decides when the parameters get parsed:
parse_parameters "${1:-}"

# The character ranges below are the C ranges, whatever locale the admin runs:
# in another one [a-z] and grep's classes take further letters, and a host that
# slipped through would end up in MariaDB's configuration and in a certificate
# (shared/ulh.md, "Hosts und Adressen"; the same check as shared/testdata/ulh/host.sh).
LC_ALL=C
export LC_ALL

# ============================================================
# WHERE EVERYTHING LIVES
# ============================================================

NGC_ETC="/etc/ngc"
NGC_TLS="/etc/ngc/db-tls"       # ca.crt, node.crt, node.key - read by MariaDB
NGC_KEYS="/etc/ngc/db-keys"     # keys.enc and keyfile.key for file_key_management
CONF_FILE="/etc/mysql/mariadb.conf.d/60-ngc.cnf"
CA_CNF="/etc/ngc/db-tls/db-ca.cnf"   # the rendered OpenSSL configuration
SST_FILE="/etc/ngc/db-keys/sst.pass" # the SST password, made once and kept

# Packages: the server, Galera's provider, the copy tool for a new node, and
# openssl for the CA and the node certificates.
NGC_PACKAGES=(mariadb-server galera-4 mariadb-backup openssl)

# The answers. parse_parameters exported them, so they are read from the
# environment; an answer nobody gave is the empty text and not an error of
# set -u. Every one of them is checked in read_answers before it is used.
NGC_HOSTNAME="${NGC_HOSTNAME:-}"
NGC_NODES="${NGC_NODES:-}"
NGC_BOOTSTRAP="${NGC_BOOTSTRAP:-no}"
NGC_PASSWORD_NGC="${NGC_PASSWORD_NGC:-}"
NGC_PASSWORD_MIGRATE="${NGC_PASSWORD_MIGRATE:-}"
NGC_CA_DIR="${NGC_CA_DIR:-/etc/ngc/db-ca}"
NGC_CSR="${NGC_CSR:-}"
NGC_PURGE="${NGC_PURGE:-no}"

NODES=()        # the checked <host>:<port> of every node, in the order given
HOSTS=()        # only their hosts, same order
NODE_NAME=""    # wsrep_node_name: the first label of NGC_HOSTNAME
SST_PASS=""     # the password for the copy to a new node, read from SST_FILE
BOOTSTRAP=0     # 1 on the node that holds the CA and makes the database
CHANGED=0       # something was written: MariaDB needs a restart
WORK=""         # temporary directory, removed on exit

# ============================================================
# SMALL HELPERS
# ============================================================

# work_init makes the temporary directory and has it removed again, whatever
# ends the script: no key and no password stays behind in /tmp.
work_init() {
	[ -n "$WORK" ] && return 0
	WORK="$(mktemp -d)" || log_error "Cannot make a temporary folder."
	chmod 0700 "$WORK"
	trap 'rm -rf "$WORK"' EXIT
}

need_root() {
	if [ "$(id -u)" != 0 ]; then
		log_error "ngc-db has to run as root: start ulh with sudo."
	fi
}

need_debian() {
	detect_os
	if [ "${PKG_TYPE:-}" != deb ]; then
		log_error "ngc-db is written for Debian and Ubuntu. This system is ${OS_DISTRO:-unknown}."
	fi
}

# valid_host - a DNS name in lower case or an IPv4 address, nothing else. No
# IPv6: MariaDB and the node list of the contract do not carry one.
valid_host() {
	local h="${1:-}" label octet
	# Only these characters, so no line break, space or quote gets further.
	case "$h" in
	'' | *[!a-z0-9.-]*) return 1 ;;
	esac
	if [ "${#h}" -gt 253 ]; then
		return 1
	fi
	label='[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?'
	if ! printf '%s\n' "$h" | grep -Eqx "($label\.)*$label"; then
		return 1
	fi
	case "${h##*.}" in
	*[!0-9]*) return 0 ;; # a DNS name: its last label is not all digits
	esac
	octet='(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])'
	printf '%s\n' "$h" | grep -Eqx "($octet\.){3}$octet"
}

# is_ipv4 says whether the host is an address and not a name. It decides
# DNS.1 against IP.1 in the certificate.
is_ipv4() {
	local octet='(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])'
	printf '%s\n' "${1:-}" | grep -Eqx "($octet\.){3}$octet"
}

# valid_port - 1 to 65535, no leading zero.
valid_port() {
	case "${1:-}" in
	'' | *[!0-9]*) return 1 ;;
	0*) return 1 ;;
	esac
	[ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

valid_host_port() {
	local hp="${1:-}"
	case "$hp" in
	*:*) ;;
	*) return 1 ;;
	esac
	valid_host "${hp%:*}" && valid_port "${hp##*:}"
}

# valid_pass - what may be a password here: 12 to 72 printable ASCII
# characters, no space and none of the characters a shell, a comma separated
# answer list or an SQL text would read as something of their own.
valid_pass() {
	local p="${1:-}"
	if [ "${#p}" -lt 12 ] || [ "${#p}" -gt 72 ]; then
		return 1
	fi
	case "$p" in
	*[!a-zA-Z0-9._@%+:/=-]*) return 1 ;;
	esac
	return 0
}

# valid_dir - an absolute path of harmless characters, no "..".
valid_dir() {
	local d="${1:-}"
	case "$d" in
	/*) ;;
	*) return 1 ;;
	esac
	case "$d" in
	*..* | *[!a-zA-Z0-9._/-]*) return 1 ;;
	esac
	[ "${#d}" -le 200 ]
}

# ensure_dir makes a folder with its owner and mode, and corrects both on a
# second run.
ensure_dir() {
	local dir="$1" owner="$2" mode="$3"
	[ -d "$dir" ] || mkdir -p "$dir"
	chown "$owner" "$dir"
	chmod "$mode" "$dir"
}

# put_file writes stdin to a file only if the content differs, and always
# atomically: a reader never sees half a configuration. It sets CHANGED when it
# wrote.
put_file() {
	local path="$1" owner="$2" mode="$3" tmp
	work_init
	tmp="$(mktemp "${WORK}/put.XXXXXX")"
	cat > "$tmp"
	chown "$owner" "$tmp"
	chmod "$mode" "$tmp"
	if [ -f "$path" ] && cmp -s "$tmp" "$path"; then
		rm -f "$tmp"
		return 0
	fi
	mv -f "$tmp" "$path"
	CHANGED=1
	log_info "written: ${path}"
}

# put_secret moves a file that was made in WORK to its place, with its owner
# and mode set BEFORE the move. WORK is 0700 and belongs to root, so a key is
# never for one moment readable where it will lie: a chmod after the write
# leaves exactly that window open.
put_secret() {
	local from="$1" to="$2"
	chown mysql:mysql "$from"
	chmod 0400 "$from"
	mv -f "$from" "$to"
	CHANGED=1
}

# ============================================================
# THE ANSWERS
# ============================================================

read_answers() {
	local hp found=0 i j

	if ! valid_host "$NGC_HOSTNAME"; then
		msg_err "The name of this node is not a DNS name in lower case and not an IPv4 address: ${NGC_HOSTNAME}"
		return 1
	fi
	NODE_NAME="${NGC_HOSTNAME%%.*}"

	NODES=()
	HOSTS=()
	for hp in $NGC_NODES; do
		if ! valid_host_port "$hp"; then
			msg_err "Not a node as <host>:<port>: ${hp}"
			return 1
		fi
		NODES+=("$hp")
		HOSTS+=("${hp%:*}")
	done
	if [ "${#NODES[@]}" -lt 1 ] || [ "${#NODES[@]}" -gt 16 ]; then
		msg_err "Name one to sixteen nodes, separated by a space."
		return 1
	fi
	for i in "${!NODES[@]}"; do
		for j in "${!NODES[@]}"; do
			if [ "$i" -lt "$j" ] && [ "${NODES[$i]}" = "${NODES[$j]}" ]; then
				msg_err "The node ${NODES[$i]} is named twice."
				return 1
			fi
		done
	done
	for i in "${!HOSTS[@]}"; do
		if [ "${HOSTS[$i]}" = "$NGC_HOSTNAME" ]; then
			found=1
		fi
	done
	if [ "$found" != 1 ]; then
		msg_err "This node (${NGC_HOSTNAME}) is not in the list of nodes."
		return 1
	fi

	case "$NGC_BOOTSTRAP" in
	yes | y | true | 1) BOOTSTRAP=1 ;;
	no | n | false | 0 | '') BOOTSTRAP=0 ;;
	*)
		msg_err "bootstrap takes yes or no, not: ${NGC_BOOTSTRAP}"
		return 1
		;;
	esac

	if ! valid_pass "$NGC_PASSWORD_NGC"; then
		msg_err "The password of the account ngc has to be 12 to 72 characters out of a-z A-Z 0-9 . _ @ % + : / = -"
		return 1
	fi
	if ! valid_pass "$NGC_PASSWORD_MIGRATE"; then
		msg_err "The password of the account ngc_migrate has to be 12 to 72 characters out of a-z A-Z 0-9 . _ @ % + : / = -"
		return 1
	fi
	if [ "$NGC_PASSWORD_NGC" = "$NGC_PASSWORD_MIGRATE" ]; then
		msg_err "The two accounts need two different passwords: ngc may only read and write, ngc_migrate may change the schema."
		return 1
	fi
	if ! valid_dir "$NGC_CA_DIR"; then
		msg_err "The folder of the CA has to be an absolute path without \"..\": ${NGC_CA_DIR}"
		return 1
	fi
	return 0
}

# ============================================================
# THE TWO TEMPLATES
# ============================================================

# render_galera prints the configuration of this node: the template
# apps/server-db/templates/galera.cnf of the NGC repository with its four marks
# (@NODE_NAME@, @NODE_ADDRESS@, @CLUSTER_ADDRESS@, @SST_PASSWORD@) replaced.
# The cluster name is not a mark: it is ngc for every installation, and no
# answer of ulh fills it.
# SST_PASS has to be read in before (load_sst_password); it is never put on a
# command line. $1 is what wsrep_cluster_address gets, so the very first start
# of the bootstrap node can pass an empty list.
render_galera() {
	local cluster_address="$1"
	cat <<EOF
# /etc/mysql/mariadb.conf.d/60-ngc.cnf
# Written by ngc-db (install, configure) from apps/server-db/templates/galera.cnf
# of the NGC repository. Never edit by hand; every line here is checked, in the
# NGC repository by TestGaleraTemplate and here by apps/cli/tests/ngc-db.test.sh.

[mysqld]
# Galera replicates InnoDB with row based logging; anything else is refused.
wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so
wsrep_cluster_name=ngc
wsrep_cluster_address=gcomm://${cluster_address}
wsrep_node_name=${NODE_NAME}
wsrep_node_address=${NGC_HOSTNAME}
binlog_format=ROW
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2

# The replication between the nodes runs over TLS against the CA of the
# installation - the same CA the API and the controller check.
wsrep_provider_options="socket.ssl_ca=${NGC_TLS}/ca.crt;socket.ssl_cert=${NGC_TLS}/node.crt;socket.ssl_key=${NGC_TLS}/node.key;socket.ssl_cipher=TLS_AES_256_GCM_SHA384"

# A new node copies the data with mariabackup, over TLS as well.
wsrep_sst_method=mariabackup
wsrep_sst_auth=sst:${SST_PASS}

# No client without TLS, and only TLS 1.3.
require_secure_transport=ON
tls_version=TLSv1.3
ssl_ca=${NGC_TLS}/ca.crt
ssl_cert=${NGC_TLS}/node.crt
ssl_key=${NGC_TLS}/node.key

# MariaDB's own encryption. The key file holds a 32 byte key, so AES-256.
plugin_load_add=file_key_management
file_key_management_filename=${NGC_KEYS}/keys.enc
file_key_management_filekey=FILE:${NGC_KEYS}/keyfile.key
file_key_management_encryption_algorithm=AES_CTR
innodb_encrypt_tables=FORCE
innodb_encrypt_log=ON
innodb_encrypt_temporary_tables=ON
encrypt_tmp_disk_tables=ON
encrypt_binlog=ON
aria_encrypt_tables=ON

# The database listens on the node's own address only; the API and the
# controllers reach it from the network, nobody else has to.
bind-address=${NGC_HOSTNAME}

# A blob may carry a canonical ui-tar (store.MaxUITotal is 64 MiB), so the
# packet limit has to be above it; the Go driver is set to the same value.
max_allowed_packet=128M

# Strict from the server side too, so a value is never quietly cut.
sql_mode=STRICT_ALL_TABLES,NO_ENGINE_SUBSTITUTION

[mariabackup]
# The copy for a new node uses the same certificates.
ssl_ca=${NGC_TLS}/ca.crt
ssl_cert=${NGC_TLS}/node.crt
ssl_key=${NGC_TLS}/node.key
EOF
}

# render_ca_cnf prints apps/server-db/templates/db-ca.cnf of the NGC repository
# with @HOST@ replaced by $1. An IPv4 address becomes IP.1, a name DNS.1 - a
# certificate with an address in DNS would not be accepted by any client.
render_ca_cnf() {
	local host="$1" alt="DNS.1"
	if is_ipv4 "$host"; then
		alt="IP.1"
	fi
	cat <<EOF
# The CA of one NGC installation and the certificates of its database nodes.
# Written by ngc-db from apps/server-db/templates/db-ca.cnf of the NGC
# repository. openssl req reads its options from the section -section names, so
# ca_dn and node_dn hold the request options and point at the section with the
# name: a section that holds the name alone makes "req -section" stop with
# "No objects specified in config file" (measured with OpenSSL 3.5.7).

[ca_dn]
prompt = no
distinguished_name = ca_name

[ca_name]
CN = NGC DB CA

[ca_ext]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash

[node_dn]
prompt = no
distinguished_name = node_name

[node_name]
CN = ${host}

[node_ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth,clientAuth
# One @ names a section; "@node_alt@" would look for a section called
# "node_alt@".
subjectAltName = @node_alt
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid

[node_alt]
${alt} = ${host}
EOF
}

# ============================================================
# PACKAGES, KEYS, CERTIFICATES
# ============================================================

ensure_packages() {
	local p todo=()
	for p in "${NGC_PACKAGES[@]}"; do
		dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || todo+=("$p")
	done
	if [ "${#todo[@]}" = 0 ]; then
		log_info "packages are there: ${NGC_PACKAGES[*]}"
		return 0
	fi
	log_section "Packages: ${todo[*]}"
	$PKG_UPDATE || true
	$PKG_INSTALL "${todo[@]}" || log_error "Could not install: ${todo[*]}"
}

# ensure_sst_password makes the password for the copy to a new node once and
# keeps it, so a second run of install writes the same configuration.
ensure_sst_password() {
	if [ -s "$SST_FILE" ] && [ "$(wc -c < "$SST_FILE")" -gt 16 ]; then
		load_sst_password
		return 0
	fi
	# 32 bytes as hex: no character that the configuration file or the shell
	# would read as something of its own.
	work_init
	openssl rand -hex 32 | tr -d '\n' > "${WORK}/sst.pass" ||
		log_error "Could not make the password for the copy to a new node."
	put_secret "${WORK}/sst.pass" "$SST_FILE"
	load_sst_password
	log_info "password for the copy to a new node: made"
}

# ensure_encryption_keys makes the keys of file_key_management: the key file
# "1;<hex of 32 random bytes>" encrypted into keys.enc, and the second random
# key that opens it in keyfile.key. The unencrypted key file is gone again
# before this function returns.
ensure_encryption_keys() {
	if [ -s "${NGC_KEYS}/keys.enc" ] && [ -s "${NGC_KEYS}/keyfile.key" ]; then
		log_info "encryption keys are there"
		return 0
	fi
	if [ -e "${NGC_KEYS}/keys.enc" ] || [ -e "${NGC_KEYS}/keyfile.key" ]; then
		log_error "Only one of ${NGC_KEYS}/keys.enc and ${NGC_KEYS}/keyfile.key is there. Do not guess: put the pair back from the backup, or remove both and let install make a new pair - the data of an older pair cannot be read afterwards."
	fi
	work_init
	local plain="${WORK}/keys.txt" pass="${WORK}/pass.txt"
	printf '1;%s\n' "$(openssl rand -hex 32)" > "$plain"
	openssl rand -base64 48 | tr -d '\n' > "$pass"
	openssl enc -aes-256-cbc -pbkdf2 -md sha256 -salt \
		-in "$plain" -out "${WORK}/keys.enc" -pass "file:${pass}" ||
		log_error "Could not encrypt the key file."
	shred -u "$plain" 2>/dev/null || rm -f "$plain"
	put_secret "${WORK}/keys.enc" "${NGC_KEYS}/keys.enc"
	put_secret "$pass" "${NGC_KEYS}/keyfile.key"
	CHANGED=1
	log_info "encryption keys made: AES-256 through a 32 byte key"
}

# ensure_ca makes the CA of the installation, only on the bootstrap node. Its
# private key stays in NGC_CA_DIR and is never copied anywhere.
ensure_ca() {
	if [ -s "${NGC_CA_DIR}/ca.key" ] && [ -s "${NGC_CA_DIR}/ca.crt" ]; then
		log_info "the CA of the installation is there"
	else
		log_section "The CA of this installation"
		openssl genpkey -algorithm ed25519 -out "${NGC_CA_DIR}/ca.key" ||
			log_error "Could not make the key of the CA."
		chown root:root "${NGC_CA_DIR}/ca.key"
		chmod 0400 "${NGC_CA_DIR}/ca.key"
		# 20 years: the CA outlives every node certificate, and nobody has to
		# turn it over while the installation runs.
		openssl req -new -x509 -key "${NGC_CA_DIR}/ca.key" -out "${NGC_CA_DIR}/ca.crt" \
			-days 7300 -config "$CA_CNF" -section ca_dn -extensions ca_ext < /dev/null ||
			log_error "Could not make the certificate of the CA."
		chmod 0444 "${NGC_CA_DIR}/ca.crt"
		log_info "CA made: ${NGC_CA_DIR}/ca.crt, 20 years"
	fi
	put_file "${NGC_TLS}/ca.crt" root:root 0444 < "${NGC_CA_DIR}/ca.crt"
}

# ensure_node_key makes the private key of this node. It never leaves this
# machine - only the request does.
ensure_node_key() {
	if [ -s "${NGC_TLS}/node.key" ]; then
		return 0
	fi
	work_init
	openssl genpkey -algorithm ed25519 -out "${WORK}/node.key" ||
		log_error "Could not make the key of this node."
	put_secret "${WORK}/node.key" "${NGC_TLS}/node.key"
	CHANGED=1
	log_info "key of this node made"
}

# cert_fits says whether node.crt is the certificate of node.key and carries
# this node's name. Only then a second run leaves it alone.
cert_fits() {
	[ -s "${NGC_TLS}/node.crt" ] || return 1
	local a b
	a="$(openssl x509 -in "${NGC_TLS}/node.crt" -noout -pubkey 2>/dev/null)" || return 1
	b="$(openssl pkey -in "${NGC_TLS}/node.key" -pubout 2>/dev/null)" || return 1
	[ "$a" = "$b" ] || return 1
	openssl x509 -in "${NGC_TLS}/node.crt" -noout -checkhost "$NGC_HOSTNAME" > /dev/null 2>&1 ||
		openssl x509 -in "${NGC_TLS}/node.crt" -noout -checkip "$NGC_HOSTNAME" > /dev/null 2>&1
}

# ensure_node_cert writes the request and, on the bootstrap node, the
# certificate with it. Another node shows its request and stops: the admin takes
# it to the bootstrap node and calls "ngc-db sign" there.
ensure_node_cert() {
	ensure_node_key
	if cert_fits; then
		log_info "the certificate of this node fits"
		return 0
	fi
	openssl req -new -key "${NGC_TLS}/node.key" -out "${NGC_TLS}/node.csr" \
		-config "$CA_CNF" -section node_dn < /dev/null ||
		log_error "Could not write the request for this node."
	chmod 0444 "${NGC_TLS}/node.csr"
	if [ "$BOOTSTRAP" = 1 ]; then
		sign_into "${NGC_TLS}/node.csr" "${NGC_TLS}/node.crt"
		chown mysql:mysql "${NGC_TLS}/node.crt"
		chmod 0444 "${NGC_TLS}/node.crt"
		CHANGED=1
		log_info "certificate of this node made"
		return 0
	fi
	printf '\n'
	log_warn "This node has no certificate yet. Its private key stays here; only the request below leaves this machine."
	printf '\n'
	cat "${NGC_TLS}/node.csr"
	printf '\n'
	printf 'Next step:\n'
	printf '  1. Copy the text above into a file on the first database server.\n'
	printf '  2. There, run ulh entry ngc-db, action sign, with that file.\n'
	printf '  3. Put the certificate it prints into %s/node.crt here and run install again.\n' "$NGC_TLS"
	log_error "Stopped before the start: without the certificate MariaDB would come up without TLS."
}

# sign_into checks a request and makes the certificate for it. The name has to
# be a host of the node list: a request for any other name is refused, so a
# request that was tampered with on the way cannot become a certificate of this
# installation.
sign_into() {
	local csr="$1" out="$2" cn host ok=0
	[ -s "${NGC_CA_DIR}/ca.key" ] || log_error "This node holds no CA. Sign on the node that was installed with bootstrap=yes."
	openssl req -in "$csr" -noout -verify > /dev/null 2>&1 ||
		log_error "The request is not readable or its signature does not fit: ${csr}"
	cn="$(openssl req -in "$csr" -noout -subject -nameopt multiline 2>/dev/null |
		sed -n 's/^ *commonName *= *//p' | head -n1)"
	[ -n "$cn" ] || log_error "The request carries no name (CN): ${csr}"
	if ! valid_host "$cn"; then
		log_error "The name of the request is not a DNS name in lower case and not an IPv4 address: ${cn}"
	fi
	for host in "${HOSTS[@]}"; do
		if [ "$host" = "$cn" ]; then
			ok=1
		fi
	done
	[ "$ok" = 1 ] || log_error "The name ${cn} is not one of the nodes: ${HOSTS[*]}"
	work_init
	local cnf="${WORK}/sign.cnf"
	render_ca_cnf "$cn" > "$cnf"
	# 10 years, and the serial file stays with the CA key.
	openssl x509 -req -in "$csr" -CA "${NGC_CA_DIR}/ca.crt" -CAkey "${NGC_CA_DIR}/ca.key" \
		-CAserial "${NGC_CA_DIR}/ca.srl" -CAcreateserial -out "$out" -days 3650 \
		-extfile "$cnf" -extensions node_ext ||
		log_error "Could not make the certificate for ${cn}."
}

# ============================================================
# CONFIGURATION AND START
# ============================================================

# cluster_list is what wsrep_cluster_address carries: every node of the list.
cluster_list() {
	local out="" hp
	for hp in "${NODES[@]}"; do
		out="${out:+${out},}${hp%:*}"
	done
	printf '%s' "$out"
}

# load_sst_password reads the kept password into SST_PASS.
load_sst_password() {
	SST_PASS="$(cat "$SST_FILE")"
	[ -n "$SST_PASS" ] || log_error "The password for the copy to a new node is empty: ${SST_FILE}"
}

write_config() {
	[ -n "$SST_PASS" ] || load_sst_password
	ensure_dir /etc/mysql/mariadb.conf.d root:root 0755
	render_galera "$(cluster_list)" | put_file "$CONF_FILE" root:root 0644
}

mariadb_running() {
	mariadb --protocol=socket -N -B -e 'SELECT 1' > /dev/null 2>&1
}

# wait_synced waits until this node is part of the cluster. Without it the
# accounts below would be made on a node that is still copying.
wait_synced() {
	local i state
	for i in $(seq 1 120); do
		state="$(mariadb --protocol=socket -N -B \
			-e "SHOW STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | cut -f2)"
		if [ "$state" = Synced ]; then
			log_info "this node is Synced"
			return 0
		fi
		sleep 2
	done
	log_error "This node did not report Synced. Look at the log: journalctl -u mariadb."
}

start_cluster() {
	if mariadb_running; then
		if [ "$CHANGED" = 1 ]; then
			log_section "Restarting MariaDB"
			systemctl restart mariadb || log_error "MariaDB did not come up again."
		fi
	elif [ "$BOOTSTRAP" = 1 ] && [ ! -f /var/lib/mysql/grastate.dat ]; then
		# The very first start of the whole cluster: this node opens it.
		log_section "Opening the cluster on this node"
		systemctl stop mariadb > /dev/null 2>&1 || true
		galera_new_cluster || log_error "galera_new_cluster did not come up."
	else
		log_section "Starting MariaDB"
		systemctl enable mariadb > /dev/null 2>&1 || true
		systemctl start mariadb || log_error "MariaDB did not come up. Is the first node running?"
	fi
	wait_synced
}

# ensure_database makes the database and the three accounts, on the bootstrap
# node only - Galera carries them to the others. The passwords go in through a
# file from mktemp with mode 0600, never on a command line and never into the
# log.
ensure_database() {
	work_init
	local sql="${WORK}/accounts.sql"
	[ -n "$SST_PASS" ] || load_sst_password
	umask 077
	cat > "$sql" <<EOF
CREATE DATABASE IF NOT EXISTS ngc CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;

CREATE USER IF NOT EXISTS 'ngc'@'%' IDENTIFIED BY '${NGC_PASSWORD_NGC}' REQUIRE SSL;
ALTER USER 'ngc'@'%' IDENTIFIED BY '${NGC_PASSWORD_NGC}' REQUIRE SSL;
GRANT SELECT, INSERT, UPDATE, DELETE ON ngc.* TO 'ngc'@'%';

CREATE USER IF NOT EXISTS 'ngc_migrate'@'%' IDENTIFIED BY '${NGC_PASSWORD_MIGRATE}' REQUIRE SSL;
ALTER USER 'ngc_migrate'@'%' IDENTIFIED BY '${NGC_PASSWORD_MIGRATE}' REQUIRE SSL;
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP, REFERENCES ON ngc.* TO 'ngc_migrate'@'%';

CREATE USER IF NOT EXISTS 'sst'@'localhost' IDENTIFIED BY '${SST_PASS}';
ALTER USER 'sst'@'localhost' IDENTIFIED BY '${SST_PASS}';
GRANT RELOAD, PROCESS, LOCK TABLES, BINLOG MONITOR, REPLICA MONITOR ON *.* TO 'sst'@'localhost';

DELETE FROM mysql.global_priv WHERE User = '';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
EOF
	chmod 0600 "$sql"
	mariadb --protocol=socket < "$sql" ||
		log_error "Could not make the database and the accounts."
	shred -u "$sql" 2>/dev/null || rm -f "$sql"
	log_info "database ngc and the accounts ngc, ngc_migrate and sst are in order"
}

show_next_steps() {
	printf '\n'
	log_section "The certificate of this installation's database CA"
	printf '\n'
	cat "${NGC_TLS}/ca.crt"
	printf '\n'
	printf 'Next steps:\n'
	printf '  1. Put the certificate above into ngc-api as db_ca, and into\n'
	printf '     ngc-controller as migrate_ca. Without it no server trusts this\n'
	printf '     database.\n'
	printf '  2. Install the other database servers with bootstrap=no. Each one\n'
	printf '     shows a request; sign it here with the action sign.\n'
	printf '  3. Check on every node:\n'
	printf "     mariadb --protocol=socket -e \"SHOW STATUS LIKE 'wsrep_cluster_size'\"\n"
}

# ============================================================
# THE ACTIONS
# ============================================================

prepare() {
	need_root
	need_debian
	read_answers || log_error "An answer is not in order. Nothing was changed."
	work_init
	ensure_dir "$NGC_ETC" root:root 0755
	# root:mysql 0710, not root:root 0700. MariaDB runs as mysql and has to
	# read ssl_cert, ssl_key, the CA and both file_key_management files that
	# lie in here; through a folder it may not enter, the chown on those files
	# would be worth nothing, and the server would come up without TLS or stop
	# at the encryption. 0710 gives mysql the way through and no listing, and
	# nobody else anything at all.
	ensure_dir "$NGC_TLS" root:mysql 0710
	ensure_dir "$NGC_KEYS" root:mysql 0710
	if [ "$BOOTSTRAP" = 1 ]; then
		# This one stays root:root 0700: the private key of the CA is the
		# whole trust of the installation, and MariaDB never reads it.
		ensure_dir "$NGC_CA_DIR" root:root 0700
	fi
	render_ca_cnf "$NGC_HOSTNAME" | put_file "$CA_CNF" root:root 0600
}

install_ngc_db() {
	log_section "NextGenCloud: MariaDB with Galera for ${NGC_HOSTNAME}"
	prepare
	ensure_packages
	# MariaDB has to be there before the keys: they belong to its user.
	ensure_sst_password
	ensure_encryption_keys
	if [ "$BOOTSTRAP" = 1 ]; then
		ensure_ca
	elif [ ! -s "${NGC_TLS}/ca.crt" ]; then
		log_error "The certificate of the CA is missing: put it into ${NGC_TLS}/ca.crt (the first node printed it) and run install again."
	fi
	ensure_node_cert
	write_config
	start_cluster
	if [ "$BOOTSTRAP" = 1 ]; then
		ensure_database
	fi
	log_info "MariaDB with Galera and TLS is running on ${NGC_HOSTNAME}."
	show_next_steps
}

configure_ngc_db() {
	log_section "NextGenCloud: changing the database configuration"
	prepare
	mariadb_running || log_error "MariaDB is not running. Use install."
	ensure_node_cert
	write_config
	start_cluster
	if [ "$BOOTSTRAP" = 1 ]; then
		ensure_database
	fi
	log_info "Configuration of ${NGC_HOSTNAME} is in order."
}

sign_ngc_db() {
	need_root
	need_debian
	read_answers || log_error "An answer is not in order. Nothing was signed."
	[ -n "$NGC_CSR" ] || log_error "Name the file with the request: sign,NGC_CSR=/pfad/node.csr"
	[ -f "$NGC_CSR" ] || log_error "No such file: ${NGC_CSR}"
	work_init
	local out="${WORK}/node.crt"
	sign_into "$NGC_CSR" "$out"
	printf '\n'
	cat "$out"
	printf '\n'
	log_info "Certificate made. Put it on that node into ${NGC_TLS}/node.crt and run install there again."
}

uninstall_ngc_db() {
	need_root
	need_debian
	# uninstall does not run read_answers - the catalog asks it for purge
	# alone - so the one path it would delete is checked right here. An rm -rf
	# on a path nobody looked at is not a thing to leave to the environment.
	if ! valid_dir "$NGC_CA_DIR"; then
		log_error "The folder of the CA is not an absolute path without two dots: ${NGC_CA_DIR}. Nothing was removed."
	fi
	log_warn "Removing MariaDB of NextGenCloud from this server."
	systemctl stop mariadb > /dev/null 2>&1 || true
	systemctl disable mariadb > /dev/null 2>&1 || true
	rm -f "$CONF_FILE"
	if [ "$NGC_PURGE" = yes ]; then
		# The warning comes BEFORE the deletion. After it, it is a log entry
		# and no warning: the key pair of /etc/ngc/db-keys is the only way to
		# read the data of this server, and it is about to be gone.
		log_warn "Now removing ${NGC_KEYS}, ${NGC_TLS} and ${NGC_CA_DIR}. Without the key pair of ${NGC_KEYS} the data in /var/lib/mysql cannot be read any more - not by this server and not by any other one. Put the pair away first if you are not sure."
		$PKG_UNINSTALL "${NGC_PACKAGES[@]}" || log_warn "Not every package could be removed."
		rm -rf "$NGC_TLS" "$NGC_KEYS" "$NGC_CA_DIR"
		log_info "Removed. /var/lib/mysql was left alone, but it cannot be read any more: delete it by hand if you want the space back."
	else
		log_info "Configuration removed. Packages, keys, certificates and the data were kept; run uninstall with purge=yes to remove them too."
	fi
}

# ============================================================
# MAIN
# ============================================================

case "$ACTION" in
install)
	install_ngc_db
	;;
configure | config)
	configure_ngc_db
	;;
sign)
	sign_ngc_db
	;;
uninstall)
	uninstall_ngc_db
	;;
*)
	# Prints the actions and their parameters from the catalog.
	print_usage ngc-db && exit 1
	;;
esac

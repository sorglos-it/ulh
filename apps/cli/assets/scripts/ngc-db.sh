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
#   7 backup_dir        NGC_BACKUP_DIR        where backup puts the file
#   8 backup_file       NGC_BACKUP_FILE       the file restore reads
#   9 restore_confirm   NGC_RESTORE_CONFIRM   yes, or restore does nothing
#
# The passphrase of a backup is NOT in that list and never becomes an answer:
# backup and restore read it themselves from the terminal without echo. An
# answer travels through the environment and through config/answer.yaml, and a
# passphrase that lies in a file beside the backup it opens is no passphrase.
#
# Everything this script prints is English, as in every other ulh script. The
# five languages of ulh sit in assets/catalog.yaml.
#
# backup writes one encrypted file of the database ngc plus its checksum;
# restore puts such a file back, and warns before it does. Neither of them ever
# puts a secret on a command line: the server is reached as root over the unix
# socket, so there is no database password to pass at all, and the passphrase of
# the file goes to openssl as "-pass file:<path>" out of a 0600 file inside the
# 0700 working folder.

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
# Galera writes its own state beside the data. It is a variable so a test can
# point cluster_state_here at a file of its own instead of replacing that
# function - a stub of the function under measurement measures the stub.
GRASTATE="${GRASTATE:-/var/lib/mysql/grastate.dat}"

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
NGC_BACKUP_DIR="${NGC_BACKUP_DIR:-}"
NGC_BACKUP_FILE="${NGC_BACKUP_FILE:-}"
NGC_RESTORE_CONFIRM="${NGC_RESTORE_CONFIRM:-no}"

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

# db_dir_owner names the owner of the two folders MariaDB reads. The group
# mysql comes with mariadb-server, and prepare makes these folders BEFORE that
# package is there: render_ca_cnf writes the OpenSSL configuration into
# NGC_TLS. On a machine that never had MariaDB, chown root:mysql therefore dies
# with "chown: invalid group" and install stops before it has written anything
# (measured on a fresh Debian 13, 17.10.2026). Until the package is there the
# folders belong to root alone - 0710 gives nobody else anything either way -
# and ensure_db_dirs hands them over as soon as the group exists.
db_dir_owner() {
	if getent group mysql > /dev/null 2>&1; then
		printf 'root:mysql'
	else
		printf 'root:root'
	fi
}

# ensure_db_dirs gives the two folders to the group mysql. It belongs AFTER
# ensure_packages: MariaDB runs as mysql and has to read ssl_cert, ssl_key, the
# CA and both file_key_management files that lie in there; through a folder it
# may not enter, the chown on those files would be worth nothing, and the
# server would come up without TLS or stop at the encryption.
ensure_db_dirs() {
	getent group mysql > /dev/null 2>&1 ||
		log_error "MariaDB is installed, but there is no group mysql. Nothing more was changed."
	ensure_dir "$NGC_TLS" root:mysql 0710
	ensure_dir "$NGC_KEYS" root:mysql 0710
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
#
# socket.ssl_cipher is the TLS 1.2 cipher LIST of Galera and nothing else: it
# goes to SSL_CTX_set_cipher_list, which knows no TLS 1.3 suite. A TLS 1.3 name
# there does not restrict TLS 1.3, it kills the server - measured on Debian 13
# with Galera 26.4.23 on 17.10.2026: "Error setting SSL cipher list to
# 'TLS_AES_256_GCM_SHA384': no cipher match", then the provider and the server
# abort. So the value is the TLS 1.2 spelling of the one suite Entwurf 4.5
# allows, and ECDSA because the CA of this installation signs Ed25519 only.
# What it buys is measured too: with this list a TLS 1.2 peer offering
# AES-128-GCM or a CBC suite gets a handshake failure, and without it both
# come through. Under TLS 1.3 Galera offers no knob at all; measured, that
# socket negotiates TLS_AES_256_GCM_SHA384 by itself.
wsrep_provider_options="socket.ssl_ca=${NGC_TLS}/ca.crt;socket.ssl_cert=${NGC_TLS}/node.crt;socket.ssl_key=${NGC_TLS}/node.key;socket.ssl_cipher=ECDHE-ECDSA-AES256-GCM-SHA384"

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
	# -md sha1 and NO -pbkdf2, although pbkdf2 is the better derivation: the
	# reader of this file is MariaDB's file_key_management, and that plugin
	# opens a "Salted__" file with the old EVP_BytesToKey of OpenSSL over SHA-1
	# and nothing else. Written with -pbkdf2 -md sha256 the file is sound and
	# MariaDB cannot read it: measured on a fresh Debian 13 on 17.10.2026,
	# "Cannot decrypt /etc/ngc/db-keys/keys.enc. Wrong key?", upon which
	# file_key_management, InnoDB and the server fall in that order. The key
	# itself is 32 random bytes and stays AES-256; what the derivation guards
	# is keyfile.key, which lies beside it as 0400 for mysql.
	openssl enc -aes-256-cbc -md sha1 -salt \
		-in "$plain" -out "${WORK}/keys.enc" -pass "file:${pass}" 2>/dev/null ||
		log_error "Could not encrypt the key file."
	# The derivation above is the one thing about this file nobody sees go
	# wrong: a file written with the wrong one decrypts fine with the wrong one
	# too, and only MariaDB says no, minutes later and about InnoDB. So read it
	# back the way MariaDB will read it, before anything is kept.
	openssl enc -d -aes-256-cbc -md sha1 -in "${WORK}/keys.enc" \
		-pass "file:${pass}" 2>/dev/null | grep -q '^1;' ||
		log_error "The key file cannot be read back the way MariaDB reads it. Nothing was kept."
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
	# NOT a pipe. put_file sets CHANGED, and on the right of a pipe it runs in a
	# subshell, where that assignment dies with the subshell. This is the one
	# file whose change has to reach start_cluster, so losing it means a new
	# configuration gets written and never applied - silently, with a tick
	# beside it. Measured on Debian 13 on 17.10.2026 with a probe inside
	# start_cluster: "action=nothing bootstrap=1 changed=0 running=yes" right
	# after the line "written: /etc/mysql/mariadb.conf.d/60-ngc.cnf".
	put_file "$CONF_FILE" root:root 0644 < <(render_galera "$(cluster_list)")
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

# cluster_state_here says whether this node already holds the state of a Galera
# cluster. The existence of grastate.dat is NOT the answer: a start that failed
# at the provider leaves one behind whose uuid is all zeroes, and a node that
# never reached a cluster must still be allowed to open one. Measured on
# Debian 13 on 17.10.2026: after a bootstrap that worked the uuid is a real one
# (seqno -1 while the server runs, safe_to_bootstrap 1); a start that fell
# recovers the position 00000000-0000-0000-0000-000000000000.
cluster_state_here() {
	local uuid
	[ -f "$GRASTATE" ] || return 1
	uuid="$(sed -n 's/^uuid:[[:space:]]*//p' "$GRASTATE" | head -1)"
	case "$uuid" in
		'' | 00000000-0000-0000-0000-000000000000) return 1 ;;
	esac
	return 0
}

# cluster_action names what this node has to do with the service, and it is a
# function of its own so the decision can be measured without a database:
# "open", "restart", "start" or "nothing".
#
# The CLUSTER comes first, not the service. The old order asked
# "is mariadbd running?" first - and the package leaves mariadbd running,
# without wsrep. So on a fresh bootstrap node the restart branch won, and a
# plain restart makes the node JOIN the cluster named in
# wsrep_cluster_address instead of opening it. With itself as the only entry
# that cannot work: measured on Debian 13 on 17.10.2026, "failed to reach
# primary view" and then "wsrep::connect(gcomm://db-1.ngc.test) failed: 7"
# after about a minute and a half. Whether mariadbd happens to be up says
# nothing about whether the cluster exists, so it is the second question now.
cluster_action() {
	if [ "$BOOTSTRAP" = 1 ] && ! cluster_state_here; then
		printf 'open'
	elif mariadb_running; then
		if [ "$CHANGED" = 1 ]; then
			printf 'restart'
		else
			printf 'nothing'
		fi
	else
		printf 'start'
	fi
}

start_cluster() {
	case "$(cluster_action)" in
	open)
		# The very first start of the whole cluster: this node opens it.
		log_section "Opening the cluster on this node"
		systemctl stop mariadb > /dev/null 2>&1 || true
		galera_new_cluster || log_error "galera_new_cluster did not come up."
		;;
	restart)
		log_section "Restarting MariaDB"
		systemctl restart mariadb || log_error "MariaDB did not come up again."
		;;
	start)
		log_section "Starting MariaDB"
		systemctl enable mariadb > /dev/null 2>&1 || true
		systemctl start mariadb || log_error "MariaDB did not come up. Is the first node running?"
		;;
	esac
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
# BACKUP AND RESTORE
# ============================================================

# The database is reached as root over the unix socket, exactly as
# ensure_database does it: root authenticates through unix_socket, so there is
# no password to hand over and none to keep anywhere. The accounts ngc and
# ngc_migrate would each need their password passed to the client, and the only
# places to pass it are a command line (readable in the process list by every
# user of the machine) or a file - and a password file that lies on the database
# server buys nothing over the socket that is already there. The plan asks for
# ngc_migrate; this is the deviation, and that is the reason.
#
# The one secret here is the passphrase of the backup file. It is read from the
# terminal without echo, written into the 0700 working folder with mode 0600 and
# given to openssl as "-pass file:<path>". Never as "-pass pass:<secret>", which
# would stand in the process list, and never as an answer of the catalog, which
# would travel through the environment and through config/answer.yaml.

BACKUP_PASS_FILE=""   # the file in WORK that holds the passphrase, 0600

# valid_file - an absolute path of harmless characters, no "..". The same
# grammar as valid_dir; a path is a path, and the name is what a reader of
# restore expects to see checked.
valid_file() {
	valid_dir "${1:-}"
}

# ask_passphrase reads the passphrase without echo and puts it into a file in
# WORK, mode 0600, set with umask BEFORE the write: a chmod afterwards leaves a
# window in which the secret lies readable. $1 says how often it is asked:
#   twice - for backup, so a typo cannot lock the file away for good
#   once  - for restore, where a wrong one simply fails
# It reads from the terminal, not from stdin: a human who pipes something in
# must not hand a passphrase over by accident.
ask_passphrase() {
	local mode="${1:-once}" first="" second="" tty=/dev/tty
	work_init
	[ -r "$tty" ] || log_error "No terminal to ask the passphrase on. backup and restore need one: the passphrase is never taken from a file or from an answer."
	printf 'Passphrase of the backup (not shown): ' > "$tty"
	IFS= read -rs first < "$tty" || true
	printf '\n' > "$tty"
	if [ "${#first}" -lt 12 ]; then
		log_error "The passphrase has to be at least 12 characters long. Nothing was written."
	fi
	if [ "$mode" = twice ]; then
		printf 'Again, to catch a typo: ' > "$tty"
		IFS= read -rs second < "$tty" || true
		printf '\n' > "$tty"
		if [ "$first" != "$second" ]; then
			log_error "The two passphrases are not the same. Nothing was written."
		fi
	fi
	BACKUP_PASS_FILE="${WORK}/pass.txt"
	(
		umask 077
		printf '%s' "$first" > "$BACKUP_PASS_FILE"
	)
	# The shell variables go now; the file lives in WORK and dies with it.
	first=""
	second=""
}

# dump_database writes the dump of ngc to $1. --hex-blob is not a nicety: every
# blob column of NGC is binary, and without it the bytes come back as broken
# text. Routines and events are not dumped because NGC has none, and a dump
# that may create them is a dump that may run code on restore.
#
# A busy server is the normal case here, not an error: mariadb-dump takes a
# consistent read view with --single-transaction, and a DDL statement of a
# running migration makes it give up. So it is tried three times, and the dump
# counts as made only when mariadb-dump wrote its own last line. That line is
# the measurement: a dump cut off in the middle (disk full, connection gone)
# can still leave exit code 0 behind, and it would come back as a database that
# is missing its last tables without a word.
dump_database() {
	local out="$1" try
	for try in 1 2 3; do
		if mariadb-dump --protocol=socket --single-transaction --skip-lock-tables \
			--hex-blob --routines=FALSE --events=FALSE --default-character-set=utf8mb4 \
			ngc > "$out" 2> "${WORK}/dump.err"; then
			if tail -n 5 "$out" | grep -q '^-- Dump completed'; then
				return 0
			fi
			log_warn "Attempt ${try}: the dump carries no end mark, so it is not complete. Trying again."
		else
			log_warn "Attempt ${try}: mariadb-dump stopped - the server was busy, or a migration was changing the schema. Trying again."
		fi
		sed -n '1,5p' "${WORK}/dump.err" >&2 || true
		rm -f "$out"
		sleep 5
	done
	log_error "Could not write a complete dump of ngc in three attempts. Nothing was put into the backup folder."
}

# list_tables prints the base tables of the database $1, one per line. $1 is a
# name this script made itself (ngc, ngc_restore_<stamp>, ngc_before_<stamp>),
# never one that came from outside.
list_tables() {
	mariadb --protocol=socket -N -B -e \
		"SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$1' AND TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME"
}

# valid_table - a name this script is willing to put between backticks. The
# table names of a restore come out of the backup file, so they come from
# outside: a name with a backtick in it would end the quoting of the RENAME
# statement below and start something of its own. Letters, digits and the
# underscore, as MariaDB's unquoted names allow, and nothing else.
valid_table() {
	case "${1:-}" in
	'' | *[!a-zA-Z0-9_]*) return 1 ;;
	esac
	[ "${#1}" -le 64 ]
}

# drop_database removes a database this script made itself a moment ago. It is
# the way back out of a restore that failed before anything was renamed - at
# that point ngc has not been touched at all.
drop_database() {
	work_init
	local sql="${WORK}/drop.sql"
	umask 077
	printf 'DROP DATABASE IF EXISTS `%s`;\n' "$1" > "$sql"
	mariadb --protocol=socket < "$sql" ||
		log_warn "The half-loaded database ${1} could not be removed. It is in the way of nothing, but it takes up space: remove it by hand with DROP DATABASE \`${1}\`."
	rm -f "$sql"
}

# checksum_file prints the name of the checksum that belongs to a backup.
checksum_file() {
	printf '%s.sha256' "$1"
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
	ensure_dir "$NGC_TLS" "$(db_dir_owner)" 0710
	ensure_dir "$NGC_KEYS" "$(db_dir_owner)" 0710
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
	ensure_db_dirs
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
	ensure_db_dirs
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

backup_ngc_db() {
	need_root
	need_debian
	if ! valid_dir "$NGC_BACKUP_DIR"; then
		log_error "The folder for the backup has to be an absolute path without \"..\" and without a space: ${NGC_BACKUP_DIR}"
	fi
	[ -d "$NGC_BACKUP_DIR" ] || log_error "No such folder: ${NGC_BACKUP_DIR}. Make it first, on the disk the backup is supposed to lie on."
	mariadb_running || log_error "MariaDB is not running on this node, so there is nothing to read. Start it and try again."
	log_section "Backing up the database ngc"
	work_init
	ask_passphrase twice

	local stamp target plain
	stamp="$(date -u +%Y%m%dT%H%M%SZ)"
	target="${NGC_BACKUP_DIR}/ngc-${stamp}.sql.enc"
	plain="${WORK}/ngc.sql"
	umask 077
	dump_database "$plain"
	log_info "dump written: $(wc -c < "$plain") bytes"

	# 600000 rounds of PBKDF2, so a passphrase that is only good survives being
	# tried offline for a while. openssl puts the salt into the file itself.
	openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -salt \
		-in "$plain" -out "${WORK}/ngc.sql.enc" -pass "file:${BACKUP_PASS_FILE}" ||
		log_error "Could not encrypt the dump. Nothing was put into ${NGC_BACKUP_DIR}."
	# The readable dump and the passphrase go before the encrypted file is
	# moved into place: they lie in WORK, which is 0700 and root's, and they
	# have no business outliving this line. WORK would take them along at the
	# end anyway - this is earlier, and earlier is the whole point.
	shred -u "$plain" 2>/dev/null || rm -f "$plain"
	shred -u "$BACKUP_PASS_FILE" 2>/dev/null || rm -f "$BACKUP_PASS_FILE"

	chmod 0600 "${WORK}/ngc.sql.enc"
	mv -f "${WORK}/ngc.sql.enc" "$target"
	( cd "$NGC_BACKUP_DIR" && sha256sum "$(basename "$target")" ) > "$(checksum_file "$target")" ||
		log_error "The backup lies in ${target}, but its checksum could not be written."
	chmod 0644 "$(checksum_file "$target")"

	log_info "backup: ${target}"
	log_info "checksum: $(checksum_file "$target")"
	printf '\n'
	log_warn "Without that passphrase nobody opens this file again - not you and not NextGenCloud. There is no second way in: keep it somewhere other than beside the backup."
	# Nothing here removes an old backup, and nothing anywhere else does
	# either. A script that may be the last thing still working does not
	# delete backups - but the human has to know that, or the disk fills up
	# without a word.
	log_warn "Every run of backup writes one more file into ${NGC_BACKUP_DIR} and removes none. Nothing cleans that folder up: look at it now and then, and if you want a rule, write one on purpose."
}

restore_ngc_db() {
	need_root
	need_debian
	if ! valid_file "$NGC_BACKUP_FILE"; then
		log_error "Name the backup as an absolute path without \"..\" and without a space: ${NGC_BACKUP_FILE}"
	fi
	[ -f "$NGC_BACKUP_FILE" ] || log_error "No such file: ${NGC_BACKUP_FILE}"
	mariadb_running || log_error "MariaDB is not running on this node. Start it and try again."
	log_section "Putting a backup of the database ngc back"
	work_init

	# The checksum first, and before the passphrase is asked: a file that was
	# damaged on its way here is not a question for a human.
	local sums
	sums="$(checksum_file "$NGC_BACKUP_FILE")"
	[ -f "$sums" ] || log_error "The checksum is missing: ${sums}. Without it nobody can tell whether the backup arrived whole."
	( cd "$(dirname "$NGC_BACKUP_FILE")" && sha256sum -c --status "$(basename "$sums")" ) ||
		log_error "The checksum does not fit: ${NGC_BACKUP_FILE} is not the file that was backed up. Nothing was changed."
	log_info "checksum fits"

	ask_passphrase once
	local plain="${WORK}/ngc.sql"
	umask 077
	openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 \
		-in "$NGC_BACKUP_FILE" -out "$plain" -pass "file:${BACKUP_PASS_FILE}" 2> "${WORK}/dec.err" ||
		log_error "Could not decrypt the backup. Either the passphrase is wrong or the file is not a backup of ngc-db. Nothing was changed."
	# A wrong passphrase can also leave bytes behind that decrypted without a
	# complaint, so the content itself is looked at: a dump of MariaDB names
	# itself in its first line, and a complete one says so again at its end.
	if ! head -n 1 "$plain" | grep -qE '^-- (MariaDB|MySQL) dump'; then
		log_error "What came out is not a dump of MariaDB. Either the passphrase is wrong or the file is something else. Nothing was changed."
	fi
	if ! tail -n 5 "$plain" | grep -q '^-- Dump completed'; then
		log_error "The dump in this file carries no end mark, so it is not complete. Putting it back would leave the database missing its last tables. Nothing was changed."
	fi
	# The dump is loaded into a database of this script's choosing, so it may
	# not pick one of its own: a CREATE DATABASE or a USE inside it would step
	# straight out of that database and write wherever it likes. backup never
	# writes either of them (it dumps one database without --databases), so a
	# file that carries one is not a file this script wrote.
	if grep -qiE '^[[:space:]]*(CREATE[[:space:]]+DATABASE|CREATE[[:space:]]+SCHEMA|USE[[:space:]])' "$plain"; then
		log_error "This dump names a database of its own (CREATE DATABASE or USE). A backup of ngc-db does not; this file is not one. Nothing was changed."
	fi
	# DEFINER= is how a view, a trigger, a routine or an event says which
	# account it runs as. backup dumps none of them (--routines=FALSE
	# --events=FALSE, and NGC has no views and no triggers), so a file that
	# carries one would run code here that nobody asked for.
	if grep -qi 'DEFINER[[:space:]]*=' "$plain"; then
		log_error "This dump carries a view, a trigger or a routine (DEFINER=). A backup of ngc-db carries only tables and rows. Nothing was changed."
	fi
	# The passphrase has done its work; it goes before the question is asked,
	# so it is not lying there while a human thinks about the answer.
	shred -u "$BACKUP_PASS_FILE" 2>/dev/null || rm -f "$BACKUP_PASS_FILE"
	log_info "a complete dump of MariaDB, $(wc -c < "$plain") bytes"

	# The warning comes BEFORE anything is changed, as it does in uninstall.
	# After the change it is a log entry and no warning.
	printf '\n'
	log_warn "The database ngc will be replaced by this backup. THIS DOES NOT STOP AT THIS SERVER: Galera carries every statement to every other node of the cluster, so the data of the whole installation are replaced, not the data of this machine. Everything that is in ngc now is written by nobody again."
	log_warn "What is in ngc now is kept, under the name this run will print, and only a DROP DATABASE by hand removes it. Until you run that, the installation needs room for both: the old data and the new ones."
	case "$NGC_RESTORE_CONFIRM" in
	yes | y | true | 1) ;;
	*)
		log_error "Not confirmed, so nothing was changed. Run restore again and answer the question with yes."
		;;
	esac

	# Not "DROP DATABASE ngc and load into it". Between that DROP and the last
	# statement of the dump, ngc is neither the old state nor the new one, and
	# nothing brings the old one back - and restore is the command people reach
	# for when something is already broken. So: load into a database of its
	# own, and only when that worked move the names. At no point is there a
	# moment in which the old data are gone and the new ones not there.
	#
	# The price, and it is a real one: while this runs, the installation needs
	# room for BOTH copies, and the old one stays until a human removes it.
	# MariaDB has no RENAME DATABASE, so the names move table by table with
	# RENAME TABLE. One RENAME TABLE statement is atomic and MariaDB takes the
	# lock for the whole statement, so all tables of one direction go in one
	# statement; MariaDB does the pairs left to right, so a failure in the
	# middle leaves tables in two databases - but it leaves them, it does not
	# delete them, and the message below says where they are.
	local stamp fresh kept sql tables old_tables t n=0
	stamp="$(date -u +%Y%m%d%H%M%S)"
	fresh="ngc_restore_${stamp}"
	kept="ngc_before_${stamp}"
	sql="${WORK}/restore.sql"
	umask 077

	log_info "loading the backup into ${fresh} - ngc is not touched yet"
	{
		printf 'CREATE DATABASE `%s` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;\n' "$fresh"
		printf 'USE `%s`;\n' "$fresh"
		cat "$plain"
	} > "$sql"
	if ! mariadb --protocol=socket < "$sql"; then
		drop_database "$fresh"
		log_error "The backup could not be loaded. The database ngc was NOT touched: it is exactly as it was before this run. Look at the output above and try again."
	fi
	shred -u "$plain" 2>/dev/null || rm -f "$plain"
	shred -u "$sql" 2>/dev/null || rm -f "$sql"

	# A dump that ran through without a table is not a restore. This is the
	# step that tells "the name says ngc" from "the data are there".
	tables="$(list_tables "$fresh")"
	for t in $tables; do
		if ! valid_table "$t"; then
			drop_database "$fresh"
			log_error "The backup carries a table whose name this script will not put into a statement: ${t}. Nothing of ngc was touched."
		fi
		n=$((n + 1))
	done
	if [ "$n" -lt 1 ]; then
		drop_database "$fresh"
		log_error "The backup loaded without a single table. That is not a backup of ngc. The database ngc was NOT touched."
	fi
	log_info "${n} tables came out of the backup"

	# ngc has to exist for its tables to be moved out of it, and it may not
	# exist for the new ones to be moved in - so: make it if it is missing,
	# move what is in it aside, then move the new ones in.
	old_tables="$(list_tables ngc)"
	for t in $old_tables; do
		if ! valid_table "$t"; then
			drop_database "$fresh"
			log_error "The database ngc holds a table whose name this script will not put into a statement: ${t}. Nothing was changed; remove or rename that table by hand first."
		fi
	done
	{
		printf 'CREATE DATABASE IF NOT EXISTS `ngc` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;\n'
		printf 'CREATE DATABASE `%s` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;\n' "$kept"
		if [ -n "$old_tables" ]; then
			printf 'RENAME TABLE'
			for t in $old_tables; do
				printf ' `ngc`.`%s` TO `%s`.`%s`,' "$t" "$kept" "$t"
			done
			printf ';\n'
		fi
		printf 'RENAME TABLE'
		for t in $tables; do
			printf ' `%s`.`%s` TO `ngc`.`%s`,' "$fresh" "$t" "$t"
		done
		printf ';\n'
	} | sed 's/,;$/;/' > "$sql"
	if ! mariadb --protocol=socket < "$sql"; then
		rm -f "$sql"
		log_error "Moving the tables onto the name ngc failed. NOTHING WAS DELETED: what was in ngc is in ${kept} or still in ngc, and what came out of the backup is in ${fresh} or already in ngc. Look at the output above, put the names right by hand, and do not run restore again until you have."
	fi
	rm -f "$sql"
	# The now empty database of the load. The OLD data are NOT dropped here -
	# that is the one irreversible step, and a human does it, not a script.
	drop_database "$fresh"
	log_info "The backup is in the database ngc: ${n} tables."
	log_info "What was in ngc before this run is in ${kept}, untouched."

	printf '\n'
	printf 'Next steps:\n'
	printf '  1. The schema is the one of the backup. Bring it up to the API that\n'
	printf '     runs now, on the API server:\n'
	printf '       ngc-api migrate\n'
	printf '     ngc-db cannot do that here: ngc-api is not installed on a\n'
	printf '     database server.\n'
	printf '  2. Count what came back:\n'
	printf '       mariadb --protocol=socket ngc -e "SELECT COUNT(*) FROM ngc_user; SELECT COUNT(*) FROM ngc_blob;"\n'
	printf '  3. On every other node, see that it took the change:\n'
	printf "       mariadb --protocol=socket -e \"SHOW STATUS LIKE 'wsrep_cluster_size'\"\n"
	printf '  4. When you are sure the new state is the right one, and only\n'
	printf '     then, the old data go - by hand, because this is the step that\n'
	printf '     cannot be undone:\n'
	printf '       mariadb --protocol=socket -e "DROP DATABASE \\`%s\\`"\n' "$kept"
	printf '     Until you do, the installation carries both states.\n'
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
backup)
	backup_ngc_db
	;;
restore)
	restore_ngc_db
	;;
uninstall)
	uninstall_ngc_db
	;;
*)
	# Prints the actions and their parameters from the catalog.
	print_usage ngc-db && exit 1
	;;
esac

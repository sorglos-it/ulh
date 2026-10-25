#!/bin/bash

# ngc-api - NextGenCloud: the API server (Debian and Ubuntu).
#
# What it does: the programs ngc-api and ngc-store in /usr/lib/ngc/, the keys of
# this node, /etc/ngc/api.json, the service ngc-api.service, and at the end the
# setup code of the first admin account and the fingerprint of the TLS key that
# every other part of the installation is going to trust. Contract: shared/ulh.md
# of the NGC repository (github.com/sorglos-it/nextgencloud), rules "TLS intern,
# nie ungeprueft", "Hosts und Adressen" and the release check of
# shared/testdata/release/verify.sh.
#
# The prompts of assets/catalog.yaml carry the answers of that contract, in this
# order (ulh joins them with commas, so no answer may hold a comma - that is why
# the node list is separated by spaces and a password with a comma is refused):
#   1  node         NGC_NODE         name of this API in the trust list
#   2  hostname     NGC_HOSTNAME     name or IPv4 address the others reach it by
#   3  db_driver    NGC_DB_DRIVER    mariadb
#   4  db_nodes     NGC_DB_NODES     <host>:<port> of every database node
#   5  db_name      NGC_DB_NAME      the database
#   6  db_user      NGC_DB_USER      the account that reads and writes
#   7  db_password  NGC_DB_PASSWORD  its password
#   8  db_ca        NGC_DB_CA        file with the CA certificate ngc-db printed
#   9  store_url    NGC_STORE_URL    the app store, empty for the official one
#   10 store_key    NGC_STORE_KEY    its public key, empty for the official one
#   11 join_code    NGC_JOIN_CODE    empty on the first API, else the join code
#
# The certificate of this server is not in that list and never becomes an answer:
# ngc-api makes it itself at its first start, self-signed for hostname, and only
# the fingerprint of its key carries trust (shared/ulh.md). This script prints
# that fingerprint; it never makes a key of the TLS kind.
#
# Everything this script prints is English, as in every other ulh script. The
# five languages of ulh sit in assets/catalog.yaml.
#
# The program files come from NGC_RELEASE_BASE, or from /var/lib/ngc/staged when
# a release.json lies there - put the files in by hand and no network is needed.
# As long as NGC has published no release at all, that second way is the only
# one that works.

set -eu
source "$(dirname "$0")/../../classes/bootstrap.sh"
# The script itself decides when the parameters get parsed:
parse_parameters "${1:-}"

# The character ranges below are the C ranges, whatever locale the admin runs:
# in another one [a-z] and grep's classes take further letters, and a host that
# slipped through would end up in api.json and in the certificate of this server
# (shared/ulh.md, "Hosts und Adressen"; the same check as shared/testdata/ulh/host.sh).
LC_ALL=C
export LC_ALL

# ============================================================
# WHERE EVERYTHING LIVES (package config of the NGC contract)
# ============================================================

NGC_ETC="/etc/ngc"                       # config.Dir
NGC_TLS="/etc/ngc/tls"
NGC_API_JSON="/etc/ngc/api.json"         # config.APIFile
NGC_CERT="/etc/ngc/tls/api.crt"          # made by ngc-api itself
NGC_KEY="/etc/ngc/tls/api.key"
NGC_BIN="/usr/lib/ngc"                   # config.BinDir
NGC_DATA="/var/lib/ngc"                  # config.DataDir
NGC_SEQ="/var/lib/ngc/release.seq"       # the release installed last
NGC_STAGE="/var/lib/ngc/staged"          # config.StageDir: release files put here by hand
NGC_SETUP_CODE="/var/lib/ngc/setup-code" # written by ngc-api, read by root only
NGC_JOIN_SECRET="/run/ngc/join-secret"   # the keys of the installation, after a join
NGC_KEPT="/var/lib/ngc/api"              # uninstall keeps the configuration here
UNIT_FILE="/etc/systemd/system/ngc-api.service"
UNIT_NAME="ngc-api.service"              # config.ServiceAPI
API_PORT=7443                            # config.APIPort

# Packages: openssl and jq for the check of the program files, curl to fetch the
# release, ca-certificates so that it can reach the release server at all.
NGC_PACKAGES=(openssl jq curl ca-certificates)

# Where the release files come from. The address carries no trust at all: the
# signature of release.json and the SHA-256 of the file do (verify_release), so
# a mirror, NGC_RELEASE_BASE or a copy in /var/lib/ngc/staged is exactly as
# safe as this one.
NGC_RELEASE_BASE="${NGC_RELEASE_BASE:-https://github.com/sorglos-it/nextgencloud/releases/latest/download}"

# The public key of NGC's releases (sign.PurposeRelease), fixed in the script.
# It is the whole trust in a release, and it goes into api.json as releaseKey so
# that the API judges an update by the same key. The placeholder below is not a
# key, so every install stops at the check - which is the safe way round until
# the real key is in here.
NGC_RELEASE_KEY="-----BEGIN PUBLIC KEY-----
REPLACE-THIS-LINE-WITH-THE-NGC-RELEASE-KEY
-----END PUBLIC KEY-----"

# The official store of NGC, taken when the admin names none (shared/ulh.md: a
# normal installation needs neither of the two answers). Its key is a
# placeholder in the same way the release key is, so until it is real an
# installation names its own store with store_url and store_key.
NGC_STORE_URL_DEFAULT="https://store.nextgencloud.org"
NGC_STORE_KEY_DEFAULT="REPLACE-THIS-LINE-WITH-THE-NGC-STORE-KEY"

# The answers. parse_parameters exported them, so they are read from the
# environment; an answer nobody gave is the empty text and not an error of
# set -u. Every one of them is checked in read_answers before it is used.
NGC_NODE="${NGC_NODE:-}"
NGC_HOSTNAME="${NGC_HOSTNAME:-}"
NGC_DB_DRIVER="${NGC_DB_DRIVER:-mariadb}"
NGC_DB_NODES="${NGC_DB_NODES:-}"
NGC_DB_NAME="${NGC_DB_NAME:-ngc}"
NGC_DB_USER="${NGC_DB_USER:-ngc}"
NGC_DB_PASSWORD="${NGC_DB_PASSWORD:-}"
NGC_DB_CA="${NGC_DB_CA:-}"
NGC_STORE_URL="${NGC_STORE_URL:-}"
NGC_STORE_KEY="${NGC_STORE_KEY:-}"
NGC_JOIN_CODE="${NGC_JOIN_CODE:-}"
NGC_PURGE="${NGC_PURGE:-no}"

DB_NODES=()      # the checked <host>:<port> of every database node
TUNNEL_URL=""    # wss://<hostname>:7443/tunnel, what api.json calls url
STORE_URL=""     # the store that is really written
STORE_KEY=""     # and its key
CA_PEM=""        # the CA certificate of the database, read out of NGC_DB_CA
RELEASE_NAME=""  # the file of ngc-api in the release
RELEASE_ARCH=""  # amd64 or arm64, from dpkg
CHANGED=0        # something was written: the service needs a restart
WORK=""          # temporary directory, removed on exit

# ============================================================
# SMALL HELPERS
# ============================================================

# work_init makes the temporary directory and has it removed again, whatever
# ends the script: no key and nothing of a half checked release stays behind.
# 0700 and root's, so a key written in here is never for one moment readable by
# anybody else. The :? in the trap is not decoration: an empty WORK would turn
# that line into a removal of the root directory.
work_init() {
	if [ -n "$WORK" ]; then
		return 0
	fi
	WORK="$(mktemp -d)"
	chmod 0700 -- "$WORK"
	trap 'rm -rf -- "${WORK:?}"' EXIT
	trap 'exit 1' HUP INT TERM
}

# need_root stops before anything is touched: the script writes in /etc, /usr
# and /var and starts a service.
need_root() {
	if [ "$EUID" -ne 0 ]; then
		log_error "This script needs root rights. Start it from ulh, or with: sudo bash $0 \"<action>\""
	fi
}

# need_debian keeps the script to what it was written for: the package names,
# dpkg and systemd units under /etc/systemd/system are Debian's and Ubuntu's.
need_debian() {
	detect_os
	if [ "$PKG_TYPE" != "deb" ]; then
		log_error "NGC sets up its API on Debian and Ubuntu only. Found: ${OS_DISTRO}."
	fi
}

# ============================================================
# THE GRAMMAR OF NAMES, HOSTS, ADDRESSES AND KEYS
# ============================================================

# valid_host accepts a host the way NGC writes it into answer files and
# configurations: a DNS name in lower case or an IPv4 address, the subset of
# trust.ValidHost without IPv6 (an IPv6 network is reached by its name). Same
# checks in the same order as shared/testdata/ulh/host.sh, so both answer alike.
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

# valid_port: 1 to 65535 in decimal, without sign or leading zero
# (trust.ValidHostPort).
valid_port() {
	local p="${1:-}"
	case "$p" in
	'' | 0* | *[!0-9]*) return 1 ;;
	esac
	if [ "${#p}" -gt 5 ]; then
		return 1
	fi
	[ "$p" -ge 1 ] && [ "$p" -le 65535 ]
}

# valid_host_port: host ":" port, split at the last colon as trust.ValidHostPort
# does; a bracketed IPv6 host never gets here because valid_host refuses the
# brackets. The length is config.MaxField, which is what bounds a node of
# config.DB (ValidHostPort carries no bound of its own).
valid_host_port() {
	local hp="${1:-}"
	if [ "${#hp}" -gt 256 ]; then
		return 1
	fi
	case "$hp" in
	*:*) ;;
	*) return 1 ;;
	esac
	valid_host "${hp%:*}" && valid_port "${hp##*:}"
}

# valid_name: wire.ValidName - a lower case letter, then letters, digits and
# hyphens, at most 32 characters. The node name of this API in the trust list.
valid_name() {
	local n="${1:-}"
	case "$n" in
	'' | [!a-z]* | *[!a-z0-9-]*) return 1 ;;
	esac
	[ "${#n}" -le 32 ]
}

# valid_store_url: "https://", a host with an optional port, then nothing or a
# path of segments of A-Z a-z 0-9 . _ ~ - (none empty, none "." or ".."),
# without a slash at the end, user info, query or fragment; at most 256 bytes
# (trust.ValidStoreURL).
valid_store_url() {
	local u="${1:-}" rest authority path seg
	if [ "${#u}" -gt 256 ]; then
		return 1
	fi
	case "$u" in
	https://*) rest="${u#https://}" ;;
	*) return 1 ;;
	esac
	authority="${rest%%/*}"
	if ! valid_host "$authority" && ! valid_host_port "$authority"; then
		return 1
	fi
	case "$rest" in
	*/*) path="${rest#*/}" ;;
	*) return 0 ;;
	esac
	# An IFS of "/" would swallow the empty segments, and those are exactly
	# what has to be refused here, so the path is cut apart by hand.
	while :; do
		seg="${path%%/*}"
		case "$seg" in
		'' | . | .. | *[!A-Za-z0-9._~-]*) return 1 ;;
		esac
		case "$path" in
		*/*) path="${path#*/}" ;;
		*) return 0 ;;
		esac
	done
}

# valid_b64url_32: 43 characters of base64url without padding, which is what 32
# bytes come to - a key as config.API.StoreKey and every Secret of api.json
# carries it (enc.Bytes).
valid_b64url_32() {
	local s="${1:-}"
	if [ "${#s}" -ne 43 ]; then
		return 1
	fi
	case "$s" in
	*[!A-Za-z0-9_-]*) return 1 ;;
	esac
	return 0
}

# valid_pass: what may be a database password here - 8 to 72 printable ASCII
# characters, no space and none of the characters a shell, ulh's comma
# separated answer list or a database DSN would read as something of their own.
valid_pass() {
	local p="${1:-}"
	if [ "${#p}" -lt 8 ] || [ "${#p}" -gt 72 ]; then
		return 1
	fi
	case "$p" in
	*[!a-zA-Z0-9._@%+:/=-]*) return 1 ;;
	esac
	# config.DB.Validate refuses the literal [secret], the text config.Secret
	# prints in place of a password: a configuration carrying it would turn a
	# log line into a password.
	[ "$p" != "[secret]" ]
}

# valid_join_code: tunnel.JoinPrefix and base64url of the JSON behind it. Only
# ngc-api itself really reads it (tunnel.ParseJoinCode); this is its shape, so a
# typo stops here and not after the whole setup.
valid_join_code() {
	local c="${1:-}" body
	case "$c" in
	ngc-join:*) body="${c#ngc-join:}" ;;
	*) return 1 ;;
	esac
	if [ -z "$body" ] || [ "${#c}" -gt 4096 ]; then
		return 1
	fi
	case "$body" in
	*[!A-Za-z0-9_-]*) return 1 ;;
	esac
	return 0
}

# b64url_of_file prints the content of a file as base64url without padding, the
# form every key takes in api.json (enc.Bytes, config.Secret).
b64url_of_file() {
	base64 -w0 <"$1" | tr -- '+/' '-_' | tr -d '='
}

# pin_of_cert prints the pin of a certificate's key, exactly as
# shared/testdata/tls/pin.sh does: base64url without padding of the SHA-256 of
# the SubjectPublicKeyInfo. Its exit status is what the callers check
# (shared/ulh.md: a pin that could not be computed is no pin).
pin_of_cert() {
	local key pin
	# A pipeline fails only with its last command, so the key is read on its
	# own: a certificate that cannot be read must not turn into a pin.
	key="$(openssl x509 -in "$1" -noout -pubkey 2>/dev/null)" || return 1
	pin="$(printf '%s\n' "$key" | openssl pkey -pubin -outform DER 2>/dev/null |
		openssl dgst -sha256 -binary | base64 -w0 | tr '+/' '-_' | tr -d '=')"
	# A step above that failed left nothing to hash, and the SHA-256 of nothing
	# is no key's pin.
	if [ "${#pin}" -ne 43 ] || [ "$pin" = "47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU" ]; then
		return 1
	fi
	printf '%s\n' "$pin"
}

# ============================================================
# READING THE ANSWERS
# ============================================================

# read_answers checks every answer before anything is installed or written.
# Nothing unchecked may reach api.json, a service file or a command line.
read_answers() {
	local n i
	local -a nodes=()

	if ! valid_name "$NGC_NODE"; then
		log_error "This name of the API is not allowed: '${NGC_NODE}'. Take a lower case letter first, then letters, digits and hyphens, at most 32 characters - for example api-1."
	fi
	if ! valid_host "$NGC_HOSTNAME"; then
		log_error "This name of the API server is not allowed: '${NGC_HOSTNAME}'. Take a name in lower case (for example api-1.example.org) or an IPv4 address (for example 192.168.1.20). No IPv6, and nothing with https:// in front."
	fi
	TUNNEL_URL="wss://${NGC_HOSTNAME}:${API_PORT}/tunnel"

	# MariaDB only: the answers of the contract (db_nodes, db_name, db_user,
	# db_password, db_ca) are the MariaDB ones, and SQLite needs a file and a
	# 64 byte key that none of them carries. One machine on SQLite is ngc-all's
	# business, not this script's.
	if [ "$NGC_DB_DRIVER" != mariadb ]; then
		log_error "This script sets up an API against MariaDB, so db_driver is 'mariadb' and not '${NGC_DB_DRIVER}'. A single machine with SQLite is what ngc-all is for."
	fi
	read -r -a nodes <<<"$NGC_DB_NODES"
	if [ "${#nodes[@]}" -eq 0 ]; then
		log_error "The address of the database is missing, for example db-1.example.org:3306. Separate several of them with a space."
	fi
	if [ "${#nodes[@]}" -gt 16 ]; then
		log_error "At most 16 database nodes, and there are ${#nodes[@]}."
	fi
	for n in "${nodes[@]}"; do
		if ! valid_host_port "$n"; then
			log_error "This address of a database node is not allowed: '${n}'. Expected is <name or IPv4>:<port>, for example db-1.example.org:3306."
		fi
		for i in ${DB_NODES[@]+"${DB_NODES[@]}"}; do
			if [ "$i" = "$n" ]; then
				log_error "The database node ${n} is in the list twice."
			fi
		done
		DB_NODES+=("$n")
	done

	if ! valid_name "$NGC_DB_NAME"; then
		log_error "This name of the database is not allowed: '${NGC_DB_NAME}'. ngc-db makes it as 'ngc'."
	fi
	if ! valid_name "$NGC_DB_USER"; then
		log_error "This name of the database account is not allowed: '${NGC_DB_USER}'. ngc-db makes it as 'ngc'."
	fi
	if ! valid_pass "$NGC_DB_PASSWORD"; then
		log_error "The password of the database account ${NGC_DB_USER} has to be 8 to 72 characters out of a-z A-Z 0-9 . _ @ % + : / = - and nothing else. It is the password ngc-db was given for that account."
	fi
	read_db_ca

	# Both or neither (shared/ulh.md): half a store is an address nobody can
	# check, or a key for an address nobody knows.
	if [ -n "$NGC_STORE_URL" ] || [ -n "$NGC_STORE_KEY" ]; then
		if [ -z "$NGC_STORE_URL" ] || [ -z "$NGC_STORE_KEY" ]; then
			log_error "A store of your own needs both its address and its key, or neither of the two. Leave both empty for the official store of NGC."
		fi
		if ! valid_store_url "$NGC_STORE_URL"; then
			log_error "This address of the store is not allowed: '${NGC_STORE_URL}'. Expected is https://<name or IPv4>[:<port>][/<path>], without a slash at the end."
		fi
		if ! valid_b64url_32 "$NGC_STORE_KEY"; then
			log_error "The key of the store is not allowed: '${NGC_STORE_KEY}'. Expected are 43 characters out of A-Z a-z 0-9 - _ , the form the store shows."
		fi
		STORE_URL="$NGC_STORE_URL"
		STORE_KEY="$NGC_STORE_KEY"
	else
		STORE_URL="$NGC_STORE_URL_DEFAULT"
		STORE_KEY="$NGC_STORE_KEY_DEFAULT"
	fi

	if [ -n "$NGC_JOIN_CODE" ] && ! valid_join_code "$NGC_JOIN_CODE"; then
		log_error "This is no join code: '${NGC_JOIN_CODE}'. It starts with ngc-join: and the shell of the running installation shows it. Leave the answer empty on the very first API server."
	fi
}

# read_db_ca reads the CA certificate of the database out of the file the admin
# named. It is a whole PEM block and cannot travel as an answer of ulh, which
# holds one line without a comma - so the answer is the path and the file is
# read here. openssl has to accept it as a certificate: an api.json whose ca is
# none would only fail later, when the API cannot reach the database and nobody
# knows why (config.parseCA refuses it as well).
read_db_ca() {
	local f="$NGC_DB_CA"
	case "$f" in
	/*) ;;
	*) log_error "Name the CA certificate of the database as a full path, so with a / at the start. This is not one: '${f}'. It is the certificate the first database node printed at the end." ;;
	esac
	if [ ! -f "$f" ] || [ ! -r "$f" ]; then
		log_error "There is no such file, or it cannot be read: ${f}"
	fi
	# config.MaxCA is 16 KiB and a CA certificate is far below that, so a file
	# of the wrong kind is caught here and not by the API at its first start.
	if [ "$(wc -c <"$f" | tr -d ' ')" -gt 16384 ]; then
		log_error "The file ${f} is larger than 16 KiB, so it is not the CA certificate of a database (config.MaxCA)."
	fi
	if ! openssl x509 -in "$f" -noout >/dev/null 2>&1; then
		log_error "${f} is no certificate in PEM form. Take the text ngc-db printed at the end, from -----BEGIN CERTIFICATE----- to -----END CERTIFICATE-----, and put it into a file."
	fi
	# $(...) drops the trailing newlines of the file, and the one newline is put
	# back: that is how shared/testdata/config/api.json carries the field.
	CA_PEM="$(cat -- "$f")
"
}

# ============================================================
# WRITING FILES
# ============================================================

# ensure_dir makes a directory with exactly the mode it needs.
ensure_dir() {
	local d="$1" mode="$2"
	if [ ! -d "$d" ]; then
		mkdir -p -- "$d"
	fi
	chown root:root -- "$d"
	chmod "$mode" -- "$d"
}

# put_file replaces dst with src, but only when the bytes differ: a second run
# of install changes nothing that is already right, and the service is restarted
# only when something really changed (shared/ulh.md). The new file is written
# next to the old one and renamed, so a reader never sees half a file, and its
# mode is set before a single byte is in it: api.json carries keys, and a chmod
# after the write leaves exactly the window open in which they are readable.
put_file() {
	local src="$1" dst="$2" mode="$3" tmp
	if [ -f "$dst" ] && cmp -s -- "$src" "$dst"; then
		chown root:root -- "$dst"
		chmod "$mode" -- "$dst"
		log_info "unchanged: ${dst}"
		return 0
	fi
	tmp="$(mktemp -- "${dst}.XXXXXX")"
	if ! {
		chmod "$mode" -- "$tmp" &&
			chown root:root -- "$tmp" &&
			cat -- "$src" >"$tmp" &&
			mv -f -- "$tmp" "$dst"
	}; then
		rm -f -- "$tmp"
		log_error "The file ${dst} could not be written. Is the disk full?"
	fi
	CHANGED=1
	log_info "written: ${dst}"
}

# ============================================================
# THE RELEASE: FETCH, CHECK, INSTALL
# ============================================================

# b64url decodes base64url without padding from stdin, as strictly as Go's
# enc.B64: only the letters A-Z a-z 0-9 - _, and only the one encoding of the
# bytes. Same steps as shared/testdata/release/verify.sh, the template of this
# check. $(...) drops NUL bytes and trailing newlines, so the bytes are checked
# in a file first.
b64url() {
	local s pad
	cat >"$WORK/b64.in" || return 1
	case "$(tr -d 'A-Za-z0-9_-' <"$WORK/b64.in" | od -An -tx1 | tr -d ' \n')" in
	'' | 0a) ;;
	*) return 1 ;;
	esac
	s="$(cat "$WORK/b64.in")"
	case "$s" in
	*[!A-Za-z0-9_-]*) return 1 ;;
	esac
	case "$((${#s} % 4))" in
	0) pad="" ;;
	2) pad="==" ;;
	3) pad="=" ;;
	*) return 1 ;;
	esac
	printf '%s' "${s}${pad}" | tr -- '-_' '+/' >"$WORK/b64.txt"
	base64 -d <"$WORK/b64.txt" >"$WORK/b64.bin" || return 1
	base64 -w0 <"$WORK/b64.bin" >"$WORK/b64.again" || return 1
	if [ "$(tr -- '+/' '-_' <"$WORK/b64.again" | tr -d '=')" != "$s" ]; then
		return 1
	fi
	cat "$WORK/b64.bin"
}

# release_arch prints the architecture of the release files: amd64 or arm64, the
# two builds of NGC (shared/ulh.md). dpkg is asked instead of uname, because the
# packages of this system are what decides which binary fits it.
release_arch() {
	local a
	a="$(dpkg --print-architecture 2>/dev/null)" || return 1
	case "$a" in
	amd64 | arm64) printf '%s\n' "$a" ;;
	*) return 1 ;;
	esac
}

# release_payload decodes the payload of release.json into $WORK/payload.json.
# Nothing in it is trusted before verify_release has run; it is read this early
# only to learn the name of the file to fetch.
release_payload() {
	jq -er '.payload | strings' <"$1/release.json" >"$WORK/payload.txt" ||
		return 1
	b64url <"$WORK/payload.txt" >"$WORK/payload.json" || return 1
}

# release_file prints the file name of part ngc-api for this architecture: the
# last segment of the entry's url, and only if it is a name and not a path (the
# same rule as verify.sh, which checks it again).
release_file() {
	local url name
	url="$(jq -er --arg arch "$RELEASE_ARCH" '[.files[]? | select(.part == "ngc-api" and .arch == $arch)]
		| if length == 1 then .[0].url | strings else empty end' <"$WORK/payload.json")" || return 1
	name="${url##*/}"
	case "$name" in
	[A-Za-z0-9]*) ;;
	*) return 1 ;;
	esac
	case "$name" in
	*[!A-Za-z0-9._-]*) return 1 ;;
	esac
	printf '%s\n' "$name"
}

# verify_release checks the release in a directory the way shared/ulh.md
# prescribes and shared/testdata/release/verify.sh shows: the signature of
# release.json over "ngc/release/v1", a NUL byte and the payload, then the one
# entry for ngc-api and this architecture with its file name, SHA-256 and size.
# It writes nothing into the directory and says "release wrong: <reason>" when
# something is off.
verify_release() {
	(
		set -eu
		cd -- "$1"
		fail() {
			printf 'release wrong: %s\n' "$1" >&2
			exit 1
		}
		local url sum size name want got tab

		jq -er '.payload | strings' release.json >"$WORK/v.payload.txt" || fail "no payload"
		jq -er '.sig | strings' release.json >"$WORK/v.sig.txt" || fail "no signature"
		b64url <"$WORK/v.payload.txt" >"$WORK/v.payload.json" || fail "payload not base64url"
		b64url <"$WORK/v.sig.txt" >"$WORK/v.sig.bin" || fail "signature not base64url"
		{
			printf 'ngc/release/v1\0'
			cat "$WORK/v.payload.json"
		} >"$WORK/v.message.bin"
		printf '%s\n' "$NGC_RELEASE_KEY" >"$WORK/v.key.pem"
		openssl pkeyutl -verify -pubin -inkey "$WORK/v.key.pem" -rawin \
			-in "$WORK/v.message.bin" -sigfile "$WORK/v.sig.bin" >/dev/null 2>&1 ||
			fail "signature does not verify"

		tab="$(printf '\t')"
		jq -r --arg arch "$RELEASE_ARCH" '
			if (.files | type) != "array" then error("files is not a list") else . end
			| [.files[] | select(.part == "ngc-api" and .arch == $arch)]
			| if length != 1 then error("not exactly one entry") else .[0] end
			| if (.url | type) == "string" and (.sha256 | type) == "string" and (.size | type) == "number"
			then [.url, .sha256, (.size | tostring)] | @tsv else error("entry of wrong types") end
		' "$WORK/v.payload.json" >"$WORK/v.entry.tsv" || fail "no single valid entry for ngc-api ${RELEASE_ARCH}"
		IFS="$tab" read -r url sum size <"$WORK/v.entry.tsv" || fail "entry unreadable"

		name="${url##*/}"
		case "$name" in
		[A-Za-z0-9]*) ;;
		*) fail "file name not allowed: $name" ;;
		esac
		case "$name" in
		*[!A-Za-z0-9._-]*) fail "file name not allowed: $name" ;;
		esac
		if [ ! -f "$name" ]; then
			fail "file missing: $name"
		fi

		printf '%s' "$sum" | b64url >"$WORK/v.sum.bin" || fail "checksum not base64url"
		want="$(od -An -tx1 <"$WORK/v.sum.bin" | tr -d ' \n')"
		if [ "${#want}" -ne 64 ]; then
			fail "checksum not 32 bytes"
		fi
		sha256sum -- "$name" >"$WORK/v.got.txt" || fail "file unreadable: $name"
		got="$(cut -d' ' -f1 <"$WORK/v.got.txt")"
		if [ "$want" != "$got" ]; then
			fail "checksum wrong: $name"
		fi
		if [ "$(wc -c <"$name" | tr -d ' ')" != "$size" ]; then
			fail "size wrong: $name"
		fi
	)
}

# fetch_release puts release.json and the one file of ngc-api into a directory
# and leaves its name in RELEASE_NAME. /var/lib/ngc/staged is taken as it is
# when it already holds a release.json, so an installation without internet
# works with a copy put there by hand.
fetch_release() {
	local dir="$1"
	RELEASE_NAME=""
	if [ -f "${NGC_STAGE}/release.json" ]; then
		log_info "Using the release files from ${NGC_STAGE}."
		cp -f -- "${NGC_STAGE}/release.json" "${dir}/release.json"
		if ! release_payload "$dir"; then
			log_error "The file ${NGC_STAGE}/release.json is damaged."
		fi
		RELEASE_NAME="$(release_file)" || log_error "There is no entry for ngc-api ${RELEASE_ARCH} in ${NGC_STAGE}/release.json."
		if [ ! -f "${NGC_STAGE}/${RELEASE_NAME}" ]; then
			log_error "The file ${RELEASE_NAME} is missing in ${NGC_STAGE}."
		fi
		cp -f -- "${NGC_STAGE}/${RELEASE_NAME}" "${dir}/${RELEASE_NAME}"
		return 0
	fi

	log_info "Loading the program files from ${NGC_RELEASE_BASE} ..."
	if ! download "${NGC_RELEASE_BASE}/release.json" "${dir}/release.json"; then
		return 1
	fi
	if ! release_payload "$dir"; then
		log_error "The release.json that arrived is damaged. Try again later."
	fi
	# Only the name comes out of the payload, never the address: so a tampered
	# release.json cannot point the download anywhere else, and the signature
	# check right after decides everything else.
	RELEASE_NAME="$(release_file)" || log_error "There is no entry for ngc-api ${RELEASE_ARCH} in release.json. That file does not belong to this script."
	download "${NGC_RELEASE_BASE}/${RELEASE_NAME}" "${dir}/${RELEASE_NAME}"
}

# download fetches one file over HTTPS and nothing else: no other protocol, not
# even after a redirect, and never more than 256 MB.
download() {
	curl --proto '=https' --proto-redir '=https' --tlsv1.2 --location \
		--fail --silent --show-error --max-time 600 --max-filesize 268435456 \
		--output "$2" -- "$1"
}

# install_release checks the release and puts the two programs of this part into
# /usr/lib/ngc/. The signed entry of part ngc-api carries both of them in one
# archive (the migrations ride along inside ngc-api, shared/ulh.md), so one
# signature covers exactly what gets installed.
install_release() {
	local dir seq have
	dir="${WORK}/release"
	mkdir -p -- "$dir"

	case "$NGC_RELEASE_KEY" in
	*REPLACE-THIS-LINE*)
		log_error "This script has no real release key of NGC yet. Without it nobody can check whether the program files are genuine, so the setup stops here. Please get a newer version of ulh."
		;;
	esac
	RELEASE_ARCH="$(release_arch)" ||
		log_error "NGC builds its programs for amd64 and arm64. This system is neither of the two, so there is no file for it."

	if ! fetch_release "$dir"; then
		if [ -x "${NGC_BIN}/ngc-api" ] && [ -x "${NGC_BIN}/ngc-store" ] && [ -f "$NGC_SEQ" ]; then
			log_warn "The program files could not be loaded. It stays with the programs in ${NGC_BIN}, which were checked before."
			return 0
		fi
		log_error "The program files could not be loaded. Check the internet connection, or put release.json and the file of ngc-api into ${NGC_STAGE} by hand. As long as NGC has published no release, that folder is the only way that works."
	fi

	if ! verify_release "$dir"; then
		log_error "The program files are not signed by NGC (the reason is above). Nothing is installed. Get ulh again and try once more; if it stays that way, report it at github.com/sorglos-it/ulh/issues."
	fi
	log_info "The signature of the program files is good."

	# Never a release older than the one installed; the same number may come
	# again to repair an installation (shared/ulh.md). The number is read out of
	# the payload verify_release has just confirmed, not out of the one that was
	# decoded before the signature was checked.
	seq="$(jq -er '.seq | numbers' <"$WORK/v.payload.json")" || log_error "The number of the release is missing in release.json."
	case "$seq" in
	'' | *[!0-9]*) log_error "The number of the release is not a number." ;;
	esac
	have=0
	if [ -f "$NGC_SEQ" ]; then
		have="$(head -n 1 -- "$NGC_SEQ" | tr -dc '0-9')"
		have="${have:-0}"
	fi
	if [ "$seq" -lt "$have" ]; then
		log_error "The release ${seq} that arrived is older than the installed ${have}. A step backwards is not installed."
	fi
	if [ "$seq" -eq "$have" ] && [ -x "${NGC_BIN}/ngc-api" ] && [ -x "${NGC_BIN}/ngc-store" ]; then
		log_info "The programs are here in this version already (release ${seq})."
		return 0
	fi

	unpack_release "${dir}/${RELEASE_NAME}"
	ensure_dir "$NGC_DATA" 0755
	printf '%s\n' "$seq" >"${WORK}/seq"
	put_file "${WORK}/seq" "$NGC_SEQ" 0644
}

# unpack_release takes the two programs out of the checked archive. Safe
# unpacking of NGC (shared/README.md): no absolute path, no "..", no links, no
# device files - and here nothing but the two names this part carries, so a file
# that wants to land anywhere else is never written at all.
unpack_release() {
	local tarball="$1" entry p
	if ! tar -tf "$tarball" >"${WORK}/entries" 2>/dev/null; then
		log_error "The file that arrived is no archive that can be read. The release of ngc-api carries the two programs ngc-api and ngc-store in one archive."
	fi
	while IFS= read -r entry; do
		case "$entry" in
		ngc-api | ngc-store | ./ngc-api | ./ngc-store) ;;
		*) log_error "The archive holds ${entry}, and the release of ngc-api carries nothing but ngc-api and ngc-store. Nothing is unpacked." ;;
		esac
	done <"${WORK}/entries"
	# Only plain files: the first letter of tar's long listing is the kind, so
	# d, l (link), h (hard link), b, c, p and s are all refused.
	if tar -tvf "$tarball" 2>/dev/null | grep -qv '^-'; then
		log_error "The archive holds a folder, a link or a device file. Nothing is unpacked."
	fi

	mkdir -p -- "${WORK}/bin"
	tar -xf "$tarball" -C "${WORK}/bin" --no-same-owner --no-same-permissions ||
		log_error "The archive could not be unpacked."
	for p in ngc-api ngc-store; do
		if [ ! -f "${WORK}/bin/${p}" ]; then
			log_error "${p} is missing in the archive. It does not belong to this script."
		fi
	done
	ensure_dir "$NGC_BIN" 0755
	for p in ngc-api ngc-store; do
		# 0755 and root's: the API runs as root - it binds port 7443 and reads
		# api.json - and nobody else may change what it runs.
		put_file "${WORK}/bin/${p}" "${NGC_BIN}/${p}" 0755
	done
	log_info "The programs are in ${NGC_BIN}."
}

# ============================================================
# PACKAGES
# ============================================================

ensure_packages() {
	local p v
	local -a missing=()
	for p in "${NGC_PACKAGES[@]}"; do
		if ! dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q '^install ok installed$'; then
			missing+=("$p")
		fi
	done
	if [ "${#missing[@]}" -gt 0 ]; then
		log_info "Installing: ${missing[*]}"
		# PKG_UPDATE and PKG_INSTALL are commands with options, so they are
		# meant to split into words here; the package names stay quoted.
		$PKG_UPDATE || true
		$PKG_INSTALL "${missing[@]}" || log_error "These packages could not be installed: ${missing[*]}"
	else
		log_info "openssl, jq, curl and ca-certificates are installed already."
	fi
	# OpenSSL 3.0 is what the release check needs: "pkeyutl -verify -rawin" is
	# its way of checking an Ed25519 signature, and 1.1 has no -rawin at all.
	# A check that cannot run is the one thing that must not pass quietly.
	v="$(openssl version 2>/dev/null | cut -d' ' -f2)" ||
		log_error "openssl does not answer, so the program files could not be checked."
	case "$v" in
	[3-9].* | [1-9][0-9].*) log_info "openssl ${v}" ;;
	*) log_error "The release check needs openssl 3.0 or newer, and this system has ${v:-none}. Debian 12 and Ubuntu 22.04 bring 3.0; on anything older there is no way to check the signature of the program files." ;;
	esac
}

# ============================================================
# api.json
# ============================================================

# random_key prints 32 random bytes as base64url, the form every key of api.json
# takes. The bytes come from the kernel through openssl, and they go through a
# file in WORK (0700 and root's) so that no key ever stands in the argument list
# of a command, where every other process could read it.
random_key() {
	openssl rand -out "${WORK}/key.bin" 32 || log_error "No random bytes could be made."
	b64url_of_file "${WORK}/key.bin"
	rm -f -- "${WORK}/key.bin"
}

# release_key_b64 prints the release key of this script as the 32 bytes api.json
# carries (config.API.ReleaseKey): an Ed25519 public key in DER is a 12 byte
# header and the key, so the last 32 bytes of 44 are the key itself.
release_key_b64() {
	printf '%s\n' "$NGC_RELEASE_KEY" >"${WORK}/rel.pem"
	openssl pkey -pubin -in "${WORK}/rel.pem" -outform DER -out "${WORK}/rel.der" >/dev/null 2>&1 ||
		return 1
	if [ "$(wc -c <"${WORK}/rel.der" | tr -d ' ')" != 44 ]; then
		return 1
	fi
	tail -c 32 "${WORK}/rel.der" >"${WORK}/rel.key"
	b64url_of_file "${WORK}/rel.key"
}

# kept_key prints the key named $1 out of the api.json that is already there, or
# nothing. A second run of install must not draw new keys: noiseKey and signKey
# are what this node is in the trust list, and secretKey opens every secret in
# the database. New ones would lock this server out of its own installation.
#
# The line is read with sed and not with jq, so this works in the one case that
# matters most - a repair run on a server where something is broken - and the
# answer is checked by valid_b64url_32 afterwards, so only 43 characters out of
# the base64url alphabet ever come back. render_api_json writes one key per line
# in exactly this shape, so there is no second shape to read.
kept_key() {
	local k
	if [ ! -f "$NGC_API_JSON" ]; then
		return 1
	fi
	k="$(sed -n "s/^  \"$1\": \"\([A-Za-z0-9_-]*\)\",\{0,1\}\$/\1/p" <"$NGC_API_JSON" | head -n 1)"
	valid_b64url_32 "$k" || return 1
	printf '%s\n' "$k"
}

# json_text prints a text as a JSON string, with the quotes around it. Only the
# three characters that a JSON string may not carry raw are escaped - backslash,
# quote and the line break of a PEM block - and anything else that is not
# printable ASCII makes this fail instead of writing a file the API would refuse:
# every value that gets here has been through read_answers, so a character
# outside that set means something unchecked found its way in.
json_text() {
	local s="$1" out="" rest c nl
	# A line break cannot come out of $( ), which drops exactly that, so it is
	# built with a letter behind it and the letter taken off again.
	nl="$(printf '\nx')"
	nl="${nl%x}"
	# What is left after the line breaks and the printable ASCII characters
	# have been taken out has to be nothing. LC_ALL=C is set at the top of the
	# script, so \040-\176 is exactly space to tilde and not more.
	if [ "$(printf '%s' "$s" | tr -d '\n\040-\176' | wc -c | tr -d ' ')" != 0 ]; then
		return 1
	fi
	rest="$s"
	while [ -n "$rest" ]; do
		c="${rest%"${rest#?}"}"
		rest="${rest#?}"
		case "$c" in
		'\') out="${out}\\\\" ;;
		'"') out="${out}\\\"" ;;
		"$nl") out="${out}\\n" ;;
		*) out="${out}${c}" ;;
		esac
	done
	printf '"%s"' "$out"
}

# render_api_json writes /etc/ngc/api.json (config.API): strict JSON, never a
# null, and an empty field left out entirely (shared/README.md) - that is why
# sessionLifetime and idleTimeout are missing: config.parseAPI fills in its own
# defaults, and a number repeated here would be a second place to keep right.
# Every text goes through json_text, which escapes the quote, the backslash and
# the line breaks of the PEM block and refuses anything else, so one unprintable
# character stops the write instead of making a file the API cannot read. Each
# key stands on a line of its own in the shape kept_key reads back.
render_api_json() {
	local noise="$1" sign="$2" secret="$3" challenge="$4" release="$5"
	local i last
	printf '{\n'
	printf '  "node": %s,\n' "$(json_text "$NGC_NODE")"
	printf '  "url": %s,\n' "$(json_text "$TUNNEL_URL")"
	printf '  "listen": %s,\n' "$(json_text ":${API_PORT}")"
	printf '  "cert": %s,\n' "$(json_text "$NGC_CERT")"
	printf '  "certKey": %s,\n' "$(json_text "$NGC_KEY")"
	printf '  "db": {\n'
	printf '    "driver": "mariadb",\n'
	printf '    "nodes": [\n'
	last=$((${#DB_NODES[@]} - 1))
	for i in "${!DB_NODES[@]}"; do
		if [ "$i" -lt "$last" ]; then
			printf '      %s,\n' "$(json_text "${DB_NODES[$i]}")"
		else
			printf '      %s\n' "$(json_text "${DB_NODES[$i]}")"
		fi
	done
	printf '    ],\n'
	printf '    "name": %s,\n' "$(json_text "$NGC_DB_NAME")"
	printf '    "user": %s,\n' "$(json_text "$NGC_DB_USER")"
	printf '    "password": %s,\n' "$(json_text "$NGC_DB_PASSWORD")"
	printf '    "ca": %s\n' "$(json_text "$CA_PEM")"
	printf '  },\n'
	printf '  "noiseKey": "%s",\n' "$noise"
	printf '  "signKey": "%s",\n' "$sign"
	printf '  "secretKey": "%s",\n' "$secret"
	printf '  "challengeKey": "%s",\n' "$challenge"
	printf '  "releaseKey": "%s",\n' "$release"
	printf '  "storeKey": "%s",\n' "$STORE_KEY"
	printf '  "storeUrl": %s\n' "$(json_text "$STORE_URL")"
	printf '}\n'
}

# api_json_ok says whether every text of the configuration survived json_text.
# $( ) throws away the exit status of what ran inside it, so render_api_json
# cannot report a refused character by failing - this asks every value once more
# before a file is written. The keys are not asked: they come out of
# valid_b64url_32 or out of openssl, 43 characters of base64url.
api_json_ok() {
	local v
	for v in "$NGC_NODE" "$TUNNEL_URL" ":${API_PORT}" "$NGC_CERT" "$NGC_KEY" \
		"$NGC_DB_NAME" "$NGC_DB_USER" "$NGC_DB_PASSWORD" "$CA_PEM" "$STORE_URL" \
		${DB_NODES[@]+"${DB_NODES[@]}"}; do
		json_text "$v" >/dev/null || return 1
	done
	return 0
}

# write_api_json makes the keys this node needs, keeps the ones it has already,
# and writes api.json as root with mode 0600 (shared/ulh.md: configuration files
# with keys).
write_api_json() {
	local noise sign secret challenge release
	noise="$(kept_key noiseKey)" || noise="$(random_key)"
	sign="$(kept_key signKey)" || sign="$(random_key)"
	secret="$(kept_key secretKey)" || secret="$(random_key)"
	challenge="$(kept_key challengeKey)" || challenge="$(random_key)"
	release="$(release_key_b64)" ||
		log_error "The release key in this script is no Ed25519 key in PEM form, so api.json cannot be written. Please get a newer version of ulh."

	ensure_dir "$NGC_ETC" 0755
	ensure_dir "$NGC_TLS" 0755
	api_json_ok || log_error "One of the answers carries a character that may not stand in api.json. Nothing was written."
	umask 077
	render_api_json "$noise" "$sign" "$secret" "$challenge" "$release" >"${WORK}/api.json" ||
		log_error "api.json could not be made."
	put_file "${WORK}/api.json" "$NGC_API_JSON" 0600
}

# ============================================================
# JOINING A RUNNING INSTALLATION
# ============================================================

# join_installation runs ngc-api -join with the code of a running installation.
# ngc-api shows the fingerprint of the API it talks to (tunnel.JoinFingerprint)
# and the anchor of the code, so the admin can compare both with what the shell
# shows, and once an admin has signed the request it writes the two keys of the
# installation into /run/ngc/join-secret. Those two go into api.json here, over
# the random ones of write_api_json: secretKey, because every API opens the same
# secrets of the database, and challengeKey, because otherwise each server would
# answer the same unknown login name differently - and whoever asked two servers
# in turn would have the real names sorted out from the made up ones.
join_installation() {
	local secret challenge noise sign release
	log_section "Joining the running installation"
	log_warn "Compare the fingerprint and the anchor below with what the shell of the installation shows. If they differ, break this off: something else is answering there."
	"${NGC_BIN}/ngc-api" -join "$NGC_JOIN_CODE" ||
		log_error "The join did not work (the message of ngc-api is above). api.json keeps the keys of its own, so nothing of the installation was taken over; put the join code right and run the setup again."
	if [ ! -f "$NGC_JOIN_SECRET" ]; then
		log_error "ngc-api came back without writing ${NGC_JOIN_SECRET}, so the keys of the installation did not arrive. Without them this server would answer differently from every other API. Nothing was changed; run the setup again."
	fi
	secret="$(jq -er '.secretKey | strings' <"$NGC_JOIN_SECRET")" ||
		log_error "${NGC_JOIN_SECRET} carries no secretKey. Nothing was changed."
	challenge="$(jq -er '.challengeKey | strings' <"$NGC_JOIN_SECRET")" ||
		log_error "${NGC_JOIN_SECRET} carries no challengeKey. Nothing was changed."
	if ! valid_b64url_32 "$secret" || ! valid_b64url_32 "$challenge"; then
		log_error "The two keys in ${NGC_JOIN_SECRET} are not 32 bytes each. Nothing was changed."
	fi
	noise="$(kept_key noiseKey)" || log_error "api.json has no noiseKey any more. Run the setup again."
	sign="$(kept_key signKey)" || log_error "api.json has no signKey any more. Run the setup again."
	release="$(release_key_b64)" || log_error "The release key of this script cannot be read."
	api_json_ok || log_error "One of the answers carries a character that may not stand in api.json. Nothing was written."
	umask 077
	render_api_json "$noise" "$sign" "$secret" "$challenge" "$release" >"${WORK}/api.json" ||
		log_error "api.json could not be made."
	put_file "${WORK}/api.json" "$NGC_API_JSON" 0600
	# The file in /run is gone with the next start of the machine anyway; it
	# goes now, because the two keys in it are the keys of the whole
	# installation and they have no business lying about.
	shred -u -- "$NGC_JOIN_SECRET" 2>/dev/null || rm -f -- "$NGC_JOIN_SECRET"
	log_info "The keys of the installation are in api.json."
}

# joined says whether this server has taken the keys of a running installation
# already. So a second run of install does not join twice, which would draw a
# fresh node in the trust list for a server that is in it.
joined() {
	[ -f "${NGC_DATA}/joined" ]
}

mark_joined() {
	ensure_dir "$NGC_DATA" 0755
	printf '%s\n' "$NGC_NODE" >"${WORK}/joined"
	put_file "${WORK}/joined" "${NGC_DATA}/joined" 0600
}

# ============================================================
# THE SERVICE
# ============================================================

# render_unit writes ngc-api.service (config.ServiceAPI). The API runs as root:
# it binds port 7443 and reads api.json, which is 0600 and root's. What it does
# not need is taken away instead - no new privileges, a read-only system, and
# only the two places it writes.
render_unit() {
	printf '%s\n' \
		'# /etc/systemd/system/ngc-api.service' \
		'# Written by ngc-api.sh of ulh (install, configure). Never edit by hand.' \
		'[Unit]' \
		'Description=NextGenCloud API' \
		'Documentation=https://github.com/sorglos-it/nextgencloud' \
		'After=network-online.target' \
		'Wants=network-online.target' \
		'' \
		'[Service]' \
		'Type=simple' \
		"ExecStart=${NGC_BIN}/ngc-api -config ${NGC_API_JSON}" \
		'Restart=on-failure' \
		'RestartSec=5' \
		'# /run/ngc, which the join writes its answer into (join-secret,' \
		'# join-noise and join-sign, each 0600 and root).' \
		'#' \
		'# 0711 and not 0700, and the reason is not this service: the CONTROLLER' \
		'# keeps the runtime directory of every app below the same /run/ngc, and' \
		'# an app runs as its own user, so that user has to walk THROUGH here to' \
		'# reach its own. 0700 does not let it: rootless podman then falls over' \
		'# "lstat /run/ngc/<user>: permission denied" and the controller cannot' \
		'# even say whether the app runs. 0711 lets it through without letting' \
		'# it READ the directory, so no app learns the names of the others, and' \
		'# the three files above stay unreadable on their own 0600. The' \
		'# controller sets the same number itself (runtime.EnsureRun), so 0700' \
		'# here only disagreed with the program it starts.' \
		'RuntimeDirectory=ngc' \
		'RuntimeDirectoryMode=0711' \
		'NoNewPrivileges=yes' \
		'ProtectSystem=strict' \
		'ProtectHome=yes' \
		'PrivateTmp=yes' \
		'ProtectKernelTunables=yes' \
		'ProtectKernelModules=yes' \
		'ProtectControlGroups=yes' \
		'RestrictSUIDSGID=yes' \
		'RestrictNamespaces=yes' \
		'RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX' \
		'LockPersonality=yes' \
		'MemoryDenyWriteExecute=yes' \
		'SystemCallArchitectures=native' \
		"ReadWritePaths=${NGC_DATA} ${NGC_TLS}" \
		'' \
		'[Install]' \
		'WantedBy=multi-user.target'
}

# service_apply starts the API, and restarts it only when something changed: a
# running API drops every open session when it goes, so it is not restarted for
# nothing (shared/ulh.md: a second run changes nothing that is right).
service_apply() {
	systemctl daemon-reload || log_error "systemd did not take the new service file."
	if ! systemctl is-active --quiet "$UNIT_NAME"; then
		systemctl enable --now "$UNIT_NAME" ||
			log_error "The service ${UNIT_NAME} could not be started. 'journalctl -u ${UNIT_NAME}' says why."
		log_info "The API is running, and from now on it starts with the server."
		return 0
	fi
	if [ "$CHANGED" -eq 0 ]; then
		log_info "Nothing changed, the API keeps running as it is."
		return 0
	fi
	systemctl restart "$UNIT_NAME" ||
		log_error "The service ${UNIT_NAME} could not be restarted. 'journalctl -u ${UNIT_NAME}' says why."
	log_info "The API has taken the new settings."
}

# wait_for_cert waits for the certificate ngc-api makes for itself at its first
# start. Without it there is no fingerprint to show, and without that no web
# server can be set up - so this waits instead of leaving the admin without the
# one thing this script is here to print.
wait_for_cert() {
	local i=0
	while [ "$i" -lt 30 ]; do
		if [ -s "$NGC_CERT" ]; then
			return 0
		fi
		sleep 1
		i=$((i + 1))
	done
	return 1
}

# ============================================================
# THE ACTIONS
# ============================================================

configure_all() {
	write_api_json
	if [ -n "$NGC_JOIN_CODE" ] && ! joined; then
		join_installation
		mark_joined
	fi
	render_unit >"${WORK}/ngc-api.service"
	put_file "${WORK}/ngc-api.service" "$UNIT_FILE" 0644
	service_apply
}

install_ngc_api() {
	need_root
	need_debian
	work_init
	log_section "Setting up the NGC API on ${NGC_HOSTNAME}"
	read_answers
	ensure_packages
	install_release
	configure_all
	show_next_steps
}

configure_ngc_api() {
	need_root
	need_debian
	work_init
	log_section "Changing the settings of the NGC API"
	read_answers
	if [ ! -x "${NGC_BIN}/ngc-api" ]; then
		log_error "There is no API in ${NGC_BIN} yet. Call 'Set up the API' first."
	fi
	configure_all
	show_next_steps
}

uninstall_ngc_api() {
	local f
	need_root
	need_debian
	work_init
	log_section "Removing the NGC API"

	systemctl disable --now "$UNIT_NAME" >/dev/null 2>&1 || true
	rm -f -- "$UNIT_FILE"
	systemctl daemon-reload || true
	rm -f -- "${NGC_BIN}/ngc-api" "${NGC_BIN}/ngc-store"
	log_info "The service and the programs in ${NGC_BIN} are gone."

	# Only the files of ngc-api, never the whole /etc/ngc: on a server with
	# several roles web.json, controller.json and trust-anchor.json lie there
	# too and belong to other parts. /var/lib/ngc/release.seq counts for every
	# part, so it stays as well.
	if [ "$NGC_PURGE" = yes ]; then
		# The warning comes BEFORE the deletion. After it, it is a log entry
		# and no warning: secretKey of this api.json opens the secrets in the
		# database, and on a single API server it is the only copy there is.
		log_warn "Now removing ${NGC_API_JSON} and the certificate of this server. The key secretKey in api.json is what opens the secrets in the database; if this is the last API of the installation, nothing opens them again afterwards. Put the file away first if you are not sure."
		for f in "$NGC_API_JSON" "$NGC_CERT" "$NGC_KEY" "${NGC_DATA}/joined" "$NGC_SETUP_CODE"; do
			rm -f -- "$f"
		done
		rm -rf -- "${NGC_KEPT:?}"
		log_warn "Deleted: api.json, the certificate and the key of this server."
	else
		# Kept data stays under /var/lib/ngc/, so a new installation finds it
		# again (shared/ulh.md). 0700 and root's: api.json holds keys.
		ensure_dir "$NGC_KEPT" 0700
		for f in "$NGC_API_JSON" "$NGC_CERT" "$NGC_KEY"; do
			if [ -f "$f" ]; then
				cp -p -- "$f" "${NGC_KEPT}/"
			fi
		done
		log_info "Kept: api.json and the certificate stay in ${NGC_ETC}, with a copy of them under ${NGC_KEPT}."
	fi
	log_info "Done."
}

# show_next_steps prints the two things the rest of the installation waits for:
# the fingerprint of the TLS key of this server, which every web server and every
# controller checks it by (shared/ulh.md, "TLS intern, nie ungeprueft"), and on
# the very first API server the setup code of the first admin account.
show_next_steps() {
	local pin
	printf '\n'
	if ! wait_for_cert; then
		log_warn "The API has not made its certificate (${NGC_CERT}) yet, so there is no fingerprint to show. Look at 'journalctl -u ${UNIT_NAME}', and when the API is running call 'Change the settings' once more - it prints the fingerprint."
		return 0
	fi
	# The exit status of pin_of_cert decides, as shared/ulh.md asks of pin.sh: a
	# fingerprint that could not be computed is no fingerprint, and a wrong one
	# would be written into the configuration of every other part.
	pin="$(pin_of_cert "$NGC_CERT")" ||
		log_error "The certificate ${NGC_CERT} could not be read, so its fingerprint cannot be shown. Without it no web server may be set up: it is what every other part checks this API by."
	log_info "Done. What comes next:"
	printf '\n'
	printf '  The fingerprint of this API:\n'
	printf '    %s\n' "$pin"
	printf '  Type it in where ulh asks for the fingerprints of the APIs, on the\n'
	printf '  web server (ngc-web) - in the same order as their addresses.\n'
	if [ -s "$NGC_SETUP_CODE" ]; then
		printf '\n'
		printf '  The setup code for the first admin account:\n'
		printf '    %s\n' "$(cat -- "$NGC_SETUP_CODE")"
		printf '  Open the web interface in a browser and type it in there. It\n'
		printf '  works once, and the API deletes it afterwards.\n'
		printf '\n'
		log_warn "Whoever has that code makes the first admin account of this installation. Nobody needs it but you, and it is in no log."
	elif [ -n "$NGC_JOIN_CODE" ]; then
		printf '\n'
		printf '  This API joined a running installation, so there is no setup\n'
		printf '  code: its admin accounts are the ones that are there already.\n'
		printf '  Add the address of this server and the fingerprint above on\n'
		printf '  the web server.\n'
	fi
}

# ============================================================
# MAIN
# ============================================================

case "$ACTION" in
install)
	install_ngc_api
	;;
configure | config)
	configure_ngc_api
	;;
uninstall)
	uninstall_ngc_api
	;;
*)
	# Prints the actions and their parameters from the catalog.
	print_usage ngc-api && exit 1
	;;
esac

#!/bin/bash

# ngc-controller - NextGenCloud: the controller that runs on every server.
#
# What it does: the program ngc-controller into /usr/lib/ngc/, the key of this
# server made by the program itself, /etc/ngc/controller.json, the anchor in
# /etc/ngc/trust-anchor.json, the service ngc-controller.service, and podman
# from the package sources where this server carries services. Contract:
# shared/ulh.md of the NGC repository (github.com/sorglos-it/nextgencloud),
# rules "Hosts und Adressen", "Schluessel erzeugt immer der Server selbst" and
# the release check of shared/testdata/release/verify.sh.
#
# The prompts of assets/catalog.yaml carry the answers of that contract, in
# this order (ulh joins them with commas, so no answer may hold a comma - that
# is why the roles and the database nodes are separated by spaces and a
# password with a comma is refused):
#   1  name              NGC_NAME              name of this server (wire.ValidName)
#   2  pair_code         NGC_PAIR_CODE         the pairing code out of the shell
#   3  roles             NGC_ROLES             one to four of web api db services
#   4  migrate_nodes     NGC_MIGRATE_NODES     role db: <host>:<port> of every database node
#   5  migrate_name      NGC_MIGRATE_NAME      role db: the database
#   6  migrate_user      NGC_MIGRATE_USER      role db: the account for the schema (ngc_migrate)
#   7  migrate_password  NGC_MIGRATE_PASSWORD  role db: its password
#   8  migrate_ca        NGC_MIGRATE_CA        role db: file with the CA certificate of ngc-db
#
# Two things this script does NOT do, and both are the contract's:
#
#   - It makes no key of its own for the trust list. ngc-controller pair makes
#     the Noise key of this server, pairs with the API the code names, and
#     writes controller.json itself (config.SaveController, mode 0600, root's).
#     The pairing code never stands in a command line: it goes in through the
#     standard input of that call, because /proc/<pid>/cmdline is readable by
#     every local user without hidepid.
#   - It shows no pairing code and writes none into a log. What it shows at the
#     end is what ngc-controller printed: the fingerprint of this server's key
#     and the anchor out of the code, for the admin to compare with the shell.
#
# Everything this script prints is English, as in every other ulh script.

set -eu
source "$(dirname "$0")/../../classes/bootstrap.sh"
# The script itself decides when the parameters get parsed:
parse_parameters "${1:-}"

# The character ranges below are the C ranges, whatever locale the admin runs:
# in another one [a-z] and grep's classes take further letters, and a host that
# slipped through would end up in controller.json and in the DSN of the
# database driver (shared/ulh.md, "Hosts und Adressen"; the same check as
# shared/testdata/ulh/host.sh).
LC_ALL=C
export LC_ALL

# ============================================================
# WHERE EVERYTHING LIVES (package config of the NGC contract)
# ============================================================

NGC_ETC="/etc/ngc"                              # config.Dir
NGC_CONF="/etc/ngc/controller.json"             # config.ControllerFile
NGC_ANCHOR="/etc/ngc/trust-anchor.json"         # config.AnchorFile
NGC_WEB_JSON="/etc/ngc/web.json"                # config.WebFile, role web only
NGC_BIN="/usr/lib/ngc"                          # config.BinDir
NGC_DATA="/var/lib/ngc"                         # config.DataDir
NGC_SEQ="/var/lib/ngc/release.seq"              # the release installed last
NGC_STAGE="/var/lib/ngc/staged"                 # config.StageDir: release files put here by hand
NGC_STATE_DIR="/var/lib/ngc/controller"         # the local store of this controller
NGC_STATE="/var/lib/ngc/controller/state.db"    # config.Controller.DB
NGC_KEPT="/var/lib/ngc/controller-kept"         # uninstall keeps the configuration here
NGC_PAIRED="/var/lib/ngc/controller/paired"     # set once a pairing came off
UNIT_FILE="/etc/systemd/system/ngc-controller.service"
UNIT_NAME="ngc-controller.service"              # config.ServiceController
PODMAN="/usr/bin/podman"                        # config.DefaultPodman

# Packages: openssl and jq for the check of the program files, curl to fetch
# the release, ca-certificates so that it can reach the release server at all.
NGC_PACKAGES=(openssl jq curl ca-certificates)

# Where the release files come from. The address carries no trust at all: the
# signature of release.json and the SHA-256 of the file do (verify_release), so
# a mirror, NGC_RELEASE_BASE or a copy in /var/lib/ngc/staged is exactly as
# safe as this one.
NGC_RELEASE_BASE="${NGC_RELEASE_BASE:-https://github.com/sorglos-it/nextgencloud/releases/latest/download}"

# The public key of NGC's releases (sign.PurposeRelease), fixed in the script.
# It is the whole trust in a release, and it goes into controller.json as
# releaseKey so that the controller judges an update by the same key. The
# placeholder below is not a key, so every install stops at the check - which
# is the safe way round until the real key is in here.
NGC_RELEASE_KEY="-----BEGIN PUBLIC KEY-----
REPLACE-THIS-LINE-WITH-THE-NGC-RELEASE-KEY
-----END PUBLIC KEY-----"

# The answers. parse_parameters exported them, so they are read from the
# environment; an answer nobody gave is the empty text and not an error of
# set -u. Every one of them is checked in read_answers before it is used.
NGC_NAME="${NGC_NAME:-}"
NGC_PAIR_CODE="${NGC_PAIR_CODE:-}"
NGC_ROLES="${NGC_ROLES:-services}"
NGC_MIGRATE_NODES="${NGC_MIGRATE_NODES:-}"
NGC_MIGRATE_NAME="${NGC_MIGRATE_NAME:-ngc}"
NGC_MIGRATE_USER="${NGC_MIGRATE_USER:-ngc_migrate}"
NGC_MIGRATE_PASSWORD="${NGC_MIGRATE_PASSWORD:-}"
NGC_MIGRATE_CA="${NGC_MIGRATE_CA:-}"
NGC_PURGE="${NGC_PURGE:-no}"

ROLES=()          # the checked roles of this server
MIG_NODES=()      # the checked <host>:<port> of every database node
HAS_DB=0          # role db: controller.json carries migrate
HAS_WEB=0         # role web: controller.json carries webConfig
HAS_SERVICES=0    # role services: podman is installed
CA_PEM=""         # the CA certificate of the database, read out of NGC_MIGRATE_CA
RELEASE_NAME=""   # the file of ngc-controller in the release
RELEASE_ARCH=""   # amd64 or arm64, from dpkg
CHANGED=0         # something was written: the service needs a restart
WORK=""           # temporary directory, removed on exit

# ============================================================
# SMALL HELPERS
# ============================================================

# work_init makes the temporary directory and has it removed again, whatever
# ends the script. This matters more here than in any other NGC script: the
# provisional controller.json that goes into "ngc-controller pair" lies in
# here, and it carries the key that encrypts the data of every app on this
# server. 0700 and root's, so it is never for one moment readable by anybody
# else. The :? in the trap is not decoration: an empty WORK would turn that
# line into a removal of the root directory.
work_init() {
	if [ -n "$WORK" ]; then
		return 0
	fi
	WORK="$(mktemp -d)"
	chmod 0700 -- "$WORK"
	# shellcheck disable=SC2064
	trap "rm -rf -- \"\${WORK:?}\"" EXIT
}

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
		log_error "NGC sets up its controller on Debian and Ubuntu only. Found: ${OS_DISTRO}."
	fi
}

# ============================================================
# THE GRAMMAR OF NAMES, HOSTS, ADDRESSES AND KEYS
# ============================================================

# valid_host accepts a host the way NGC writes it into configurations: a DNS
# name in lower case or an IPv4 address, the subset of trust.ValidHost without
# IPv6 (an IPv6 network is reached by its name). Same checks in the same order
# as shared/testdata/ulh/host.sh, so both answer alike.
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

# valid_host_port: host ":" port, split at the last colon as
# trust.ValidHostPort does; a bracketed IPv6 host never gets here because
# valid_host refuses the brackets. The length is config.MaxField, which is what
# bounds a node of config.DB.
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
# hyphens, at most 32 characters. The name of this server.
valid_name() {
	local n="${1:-}"
	case "$n" in
	'' | [!a-z]* | *[!a-z0-9-]*) return 1 ;;
	esac
	[ "${#n}" -le 32 ]
}

# valid_db_ident: the name of a database or of a database account. This is NOT
# wire.ValidName: the account ngc-db makes is called ngc_migrate, and
# wire.ValidName has no underscore. config.DB.Validate bounds these two by
# config.MaxField alone, so the grammar is this script's - a lower case letter,
# then letters, digits and the underscore, at most 32 characters, which is what
# MariaDB takes without quoting.
valid_db_ident() {
	local n="${1:-}"
	case "$n" in
	'' | [!a-z]* | *[!a-z0-9_]*) return 1 ;;
	esac
	[ "${#n}" -le 32 ]
}

# valid_b64url_n: n characters of base64url without padding. 43 characters are
# the 32 bytes of noiseKey and releaseKey, 86 the 64 bytes of dbKey (enc.Bytes,
# config.Secret).
valid_b64url_n() {
	local s="${2:-}"
	if [ "${#s}" -ne "$1" ]; then
		return 1
	fi
	case "$s" in
	*[!A-Za-z0-9_-]*) return 1 ;;
	esac
	return 0
}

valid_b64url_32() { valid_b64url_n 43 "${1:-}"; }
valid_b64url_64() { valid_b64url_n 86 "${1:-}"; }

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

# valid_pair_code: tunnel.PairPrefix and base64url of the JSON behind it. Only
# ngc-controller itself really reads it (tunnel.ParsePairCode); this is its
# shape, so a typo stops before anything is installed.
#
# What this function must never do is name the value it refused. The code is
# the one secret of this setup, and a message carrying it would put it into the
# log of ulh - every caller below says what a code looks like instead.
valid_pair_code() {
	local c="${1:-}" body
	case "$c" in
	ngc-pair:*) body="${c#ngc-pair:}" ;;
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
# form every key takes in controller.json (enc.Bytes, config.Secret).
b64url_of_file() {
	base64 -w0 <"$1" | tr -- '+/' '-_' | tr -d '='
}

# ============================================================
# READING THE ANSWERS
# ============================================================

# read_answers checks every answer before anything is installed or written.
# Nothing unchecked may reach controller.json, a service file or a command
# line.
read_answers() {
	local r i n
	local -a names=()

	if ! valid_name "$NGC_NAME"; then
		log_error "This name of the server is not allowed: '${NGC_NAME}'. Take a lower case letter first, then letters, digits and hyphens, at most 32 characters - for example dienste."
	fi

	read -r -a names <<<"$NGC_ROLES"
	if [ "${#names[@]}" -eq 0 ]; then
		log_error "This server needs at least one role. Allowed are web, api, db and services; separate several of them with a space."
	fi
	if [ "${#names[@]}" -gt 4 ]; then
		log_error "There are four roles in all, and ${#names[@]} were given."
	fi
	for r in "${names[@]}"; do
		case "$r" in
		web | api | db | services) ;;
		*) log_error "This is no role of a server: '${r}'. Allowed are web, api, db and services." ;;
		esac
		for i in ${ROLES[@]+"${ROLES[@]}"}; do
			if [ "$i" = "$r" ]; then
				log_error "The role ${r} is in the list twice."
			fi
		done
		ROLES+=("$r")
		case "$r" in
		db) HAS_DB=1 ;;
		web) HAS_WEB=1 ;;
		services) HAS_SERVICES=1 ;;
		esac
	done

	# Only a server with the role db carries the access for the migrations,
	# and only it may carry it: config.Controller.Validate refuses a migrate
	# without that role and a role db without a migrate, both ways round.
	if [ "$HAS_DB" -eq 1 ]; then
		read_migrate
	else
		for i in "$NGC_MIGRATE_NODES" "$NGC_MIGRATE_PASSWORD" "$NGC_MIGRATE_CA"; do
			if [ -n "$i" ]; then
				log_error "This server has no role db, so it gets no access to the database for the migrations. Leave the four migrate answers empty, or add the role db."
			fi
		done
	fi

	if [ -n "$NGC_PAIR_CODE" ] && ! valid_pair_code "$NGC_PAIR_CODE"; then
		log_error "This is no pairing code. It starts with ngc-pair: and NextGenCloud shows it when you add this server there. Please insert the code completely."
	fi
}

# read_migrate checks the five answers of the role db. The account is the one
# ngc-db made for the schema (ngc_migrate), and it is a second account on
# purpose: the one the API reads and writes with may not change the schema.
read_migrate() {
	local n i
	local -a nodes=()
	read -r -a nodes <<<"$NGC_MIGRATE_NODES"
	if [ "${#nodes[@]}" -eq 0 ]; then
		log_error "The role db needs the addresses of the database nodes, for example db-1.example.org:3306. Separate several of them with a space."
	fi
	if [ "${#nodes[@]}" -gt 16 ]; then
		log_error "At most 16 database nodes, and there are ${#nodes[@]}."
	fi
	for n in "${nodes[@]}"; do
		if ! valid_host_port "$n"; then
			log_error "This address of a database node is not allowed: '${n}'. Expected is <name or IPv4>:<port>, for example db-1.example.org:3306."
		fi
		for i in ${MIG_NODES[@]+"${MIG_NODES[@]}"}; do
			if [ "$i" = "$n" ]; then
				log_error "The database node ${n} is in the list twice."
			fi
		done
		MIG_NODES+=("$n")
	done
	if ! valid_db_ident "$NGC_MIGRATE_NAME"; then
		log_error "This name of the database is not allowed: '${NGC_MIGRATE_NAME}'. ngc-db makes it as 'ngc'."
	fi
	if ! valid_db_ident "$NGC_MIGRATE_USER"; then
		log_error "This name of the database account is not allowed: '${NGC_MIGRATE_USER}'. ngc-db makes it as 'ngc_migrate'."
	fi
	if ! valid_pass "$NGC_MIGRATE_PASSWORD"; then
		log_error "The password of the database account ${NGC_MIGRATE_USER} has to be 8 to 72 characters out of a-z A-Z 0-9 . _ @ % + : / = - and nothing else. It is the password ngc-db was given for that account."
	fi
	read_migrate_ca
}

# read_migrate_ca reads the CA certificate of the database out of the file the
# admin named. It is a whole PEM block and cannot travel as an answer of ulh,
# which holds one line without a comma - so the answer is the path and the file
# is read here. openssl has to accept it as a certificate: a controller.json
# whose ca is none would only fail later, when the migrations cannot reach the
# database and nobody knows why (config.parseCA refuses it as well).
read_migrate_ca() {
	local f="$NGC_MIGRATE_CA"
	case "$f" in
	/*) ;;
	*) log_error "Name the CA certificate of the database as a full path, so with a / at the start. This is not one: '${f}'. It is the certificate the first database node printed at the end." ;;
	esac
	if [ ! -f "$f" ] || [ ! -r "$f" ]; then
		log_error "There is no such file, or it cannot be read: ${f}"
	fi
	# config.MaxCA is 16 KiB and a CA certificate is far below that, so a file
	# of the wrong kind is caught here and not by the controller at its first
	# start.
	if [ "$(wc -c <"$f" | tr -d ' ')" -gt 16384 ]; then
		log_error "The file ${f} is larger than 16 KiB, so it is not the CA certificate of a database (config.MaxCA)."
	fi
	if ! openssl x509 -in "$f" -noout >/dev/null 2>&1; then
		log_error "${f} is no certificate in PEM form. Take the text ngc-db printed at the end, from -----BEGIN CERTIFICATE----- to -----END CERTIFICATE-----, and put it into a file."
	fi
	# $(...) drops the trailing newlines of the file, and the one newline is
	# put back: that is how shared/testdata/config/api.json carries the field.
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
# of install changes nothing that is already right, and the service is
# restarted only when something really changed (shared/ulh.md). The new file is
# written next to the old one and renamed, so a reader never sees half a file,
# and its mode is set before a single byte is in it: controller.json carries
# the key of every app's data, and a chmod after the write leaves exactly the
# window open in which it is readable.
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
# check. $(...) throws away NUL bytes and trailing newlines, so the bytes are
# checked in a file first.
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

# release_arch prints the architecture of the release files: amd64 or arm64,
# the two builds of NGC (shared/ulh.md). dpkg is asked instead of uname,
# because the packages of this system are what decides which binary fits it.
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

# release_file prints the file name of part ngc-controller for this
# architecture: the last segment of the entry's url, and only if it is a name
# and not a path (the same rule as verify.sh, which checks it again).
release_file() {
	local url name
	url="$(jq -er --arg arch "$RELEASE_ARCH" '[.files[]? | select(.part == "ngc-controller" and .arch == $arch)]
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
# entry for ngc-controller and this architecture with its file name, SHA-256
# and size. It writes nothing into the directory and says "release wrong:
# <reason>" when something is off.
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
			| [.files[] | select(.part == "ngc-controller" and .arch == $arch)]
			| if length != 1 then error("not exactly one entry") else .[0] end
			| if (.url | type) == "string" and (.sha256 | type) == "string" and (.size | type) == "number"
			then [.url, .sha256, (.size | tostring)] | @tsv else error("entry of wrong types") end
		' "$WORK/v.payload.json" >"$WORK/v.entry.tsv" || fail "no single valid entry for ngc-controller ${RELEASE_ARCH}"
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

# fetch_release puts release.json and the one file of ngc-controller into a
# directory and leaves its name in RELEASE_NAME. /var/lib/ngc/staged is taken
# as it is when it already holds a release.json, so an installation without
# internet works with a copy put there by hand.
fetch_release() {
	local dir="$1"
	RELEASE_NAME=""
	if [ -f "${NGC_STAGE}/release.json" ]; then
		log_info "Using the release files from ${NGC_STAGE}."
		cp -f -- "${NGC_STAGE}/release.json" "${dir}/release.json"
		if ! release_payload "$dir"; then
			log_error "The file ${NGC_STAGE}/release.json is damaged."
		fi
		RELEASE_NAME="$(release_file)" || log_error "There is no entry for ngc-controller ${RELEASE_ARCH} in ${NGC_STAGE}/release.json."
		if [ ! -f "${NGC_STAGE}/${RELEASE_NAME}" ]; then
			log_error "The file ${RELEASE_NAME} is missing in ${NGC_STAGE}."
		fi
		cp -f -- "${NGC_STAGE}/${RELEASE_NAME}" "${dir}/${RELEASE_NAME}"
		return 0
	fi

	log_info "Loading the program file from ${NGC_RELEASE_BASE} ..."
	if ! download "${NGC_RELEASE_BASE}/release.json" "${dir}/release.json"; then
		return 1
	fi
	if ! release_payload "$dir"; then
		log_error "The release.json that arrived is damaged. Try again later."
	fi
	# Only the name comes out of the payload, never the address: so a tampered
	# release.json cannot point the download anywhere else, and the signature
	# check right after decides everything else.
	RELEASE_NAME="$(release_file)" || log_error "There is no entry for ngc-controller ${RELEASE_ARCH} in release.json. That file does not belong to this script."
	download "${NGC_RELEASE_BASE}/${RELEASE_NAME}" "${dir}/${RELEASE_NAME}"
}

# download fetches one file over HTTPS and nothing else: no other protocol, not
# even after a redirect, and never more than 256 MB.
download() {
	curl --proto '=https' --proto-redir '=https' --tlsv1.2 --location \
		--fail --silent --show-error --max-time 600 --max-filesize 268435456 \
		--output "$2" -- "$1"
}

# install_release checks the release and puts ngc-controller into
# /usr/lib/ngc/.
install_release() {
	local dir seq have
	dir="${WORK}/release"
	mkdir -p -- "$dir"

	case "$NGC_RELEASE_KEY" in
	*REPLACE-THIS-LINE*)
		log_error "This script has no real release key of NGC yet. Without it nobody can check whether the program file is genuine, so the setup stops here. Please get a newer version of ulh."
		;;
	esac
	RELEASE_ARCH="$(release_arch)" ||
		log_error "NGC builds its programs for amd64 and arm64. This system is neither of the two, so there is no file for it."

	if ! fetch_release "$dir"; then
		if [ -x "${NGC_BIN}/ngc-controller" ] && [ -f "$NGC_SEQ" ]; then
			log_warn "The program file could not be loaded. It stays with the program in ${NGC_BIN}, which was checked before."
			return 0
		fi
		log_error "The program file could not be loaded. Check the internet connection, or put release.json and the file of ngc-controller into ${NGC_STAGE} by hand. As long as NGC has published no release, that folder is the only way that works."
	fi

	if ! verify_release "$dir"; then
		log_error "The program file is not signed by NGC (the reason is above). Nothing is installed. Get ulh again and try once more; if it stays that way, report it at github.com/sorglos-it/ulh/issues."
	fi
	log_info "The signature of the program file is good."

	# Never a release older than the one installed; the same number may come
	# again to repair an installation (shared/ulh.md). The number is read out
	# of the payload verify_release has just confirmed, not out of the one that
	# was decoded before the signature was checked.
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
	if [ "$seq" -eq "$have" ] && [ -x "${NGC_BIN}/ngc-controller" ]; then
		log_info "The program is here in this version already (release ${seq})."
		return 0
	fi

	unpack_release "${dir}/${RELEASE_NAME}"
	ensure_dir "$NGC_DATA" 0755
	printf '%s\n' "$seq" >"${WORK}/seq"
	put_file "${WORK}/seq" "$NGC_SEQ" 0644
}

# unpack_release takes the program out of the checked archive. Safe unpacking
# of NGC (shared/README.md): no absolute path, no "..", no links, no device
# files - and here nothing but the one name this part carries, so a file that
# wants to land anywhere else is never written at all.
unpack_release() {
	local tarball="$1" entry
	if ! tar -tf "$tarball" >"${WORK}/entries" 2>/dev/null; then
		log_error "The file that arrived is no archive that can be read. The release of ngc-controller carries the program ngc-controller in one archive."
	fi
	while IFS= read -r entry; do
		case "$entry" in
		ngc-controller | ./ngc-controller) ;;
		*) log_error "The archive holds ${entry}, and the release of ngc-controller carries nothing but ngc-controller. Nothing is unpacked." ;;
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
	if [ ! -f "${WORK}/bin/ngc-controller" ]; then
		log_error "ngc-controller is missing in the archive. It does not belong to this script."
	fi
	ensure_dir "$NGC_BIN" 0755
	# 0755 and root's: the controller runs as root - it makes system accounts,
	# containers and the encrypted data folders - and nobody else may change
	# what it runs.
	put_file "${WORK}/bin/ngc-controller" "${NGC_BIN}/ngc-controller" 0755
	log_info "The program is in ${NGC_BIN}."
}

# ============================================================
# PACKAGES
# ============================================================

ensure_packages() {
	local p v
	local -a want=("${NGC_PACKAGES[@]}") missing=()
	# podman only where this server carries services: on a web, API or
	# database server a container engine would be a program more than the
	# server needs (shared/ulh.md).
	if [ "$HAS_SERVICES" -eq 1 ]; then
		want+=(podman)
	fi
	for p in "${want[@]}"; do
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
		log_info "Everything this server needs is installed already."
	fi
	# OpenSSL 3.0 is what the release check needs: "pkeyutl -verify -rawin" is
	# its way of checking an Ed25519 signature, and 1.1 has no -rawin at all.
	# A check that cannot run is the one thing that must not pass quietly.
	v="$(openssl version 2>/dev/null | cut -d' ' -f2)" ||
		log_error "openssl does not answer, so the program file could not be checked."
	case "$v" in
	[3-9].* | [1-9][0-9].*) log_info "openssl ${v}" ;;
	*) log_error "The release check needs openssl 3.0 or newer, and this system has ${v:-none}. Debian 12 and Ubuntu 22.04 bring 3.0; on anything older there is no way to check the signature of the program file." ;;
	esac
	# The controller starts podman by its path out of controller.json
	# (config.Controller.Podman, default /usr/bin/podman). A services server
	# whose podman is somewhere else would start no container at all, and the
	# admin would hunt the app and not the path.
	if [ "$HAS_SERVICES" -eq 1 ] && [ ! -x "$PODMAN" ]; then
		log_error "This server carries services, so it needs podman at ${PODMAN}, and there is none. Install the package podman and run the setup again."
	fi
}

# ============================================================
# controller.json
# ============================================================

# random_key prints n random bytes as base64url, the form every key of
# controller.json takes. The bytes come from the kernel through openssl, and
# they go through a file in WORK (0700 and root's) so that no key ever stands
# in the argument list of a command, where every other process could read it.
random_key() {
	openssl rand -out "${WORK}/key.bin" "$1" || log_error "No random bytes could be made."
	b64url_of_file "${WORK}/key.bin"
	rm -f -- "${WORK}/key.bin"
}

# release_key_b64 prints the release key of this script as the 32 bytes
# controller.json carries (config.Controller.ReleaseKey): an Ed25519 public key
# in DER is a 12 byte header and the key, so the last 32 bytes of 44 are the
# key itself.
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

# kept_key prints the key named $1 out of the controller.json that is already
# there, or nothing. $2 is how many characters it has to have.
#
# dbKey is the one that matters: it is what the data of every app on this
# server is encrypted with (fscrypt, per app out of this key). A new one would
# leave every app's data unreadable, and no second copy of it exists anywhere.
# The line is read with sed and not with jq, so this works in the one case that
# matters most - a repair run on a server where something is broken - and the
# answer is checked by valid_b64url_n afterwards, so only base64url of the
# right length ever comes back. render_controller_json writes one key per line
# in exactly this shape, so there is no second shape to read.
kept_key() {
	local k
	if [ ! -f "$NGC_CONF" ]; then
		return 1
	fi
	k="$(sed -n "s/^  \"$1\": \"\([A-Za-z0-9_-]*\)\",\{0,1\}\$/\1/p" <"$NGC_CONF" | head -n 1)"
	valid_b64url_n "$2" "$k" || return 1
	printf '%s\n' "$k"
}

# json_text prints a text as a JSON string, with the quotes around it. Only the
# three characters that a JSON string may not carry raw are escaped -
# backslash, quote and the line break of a PEM block - and anything else that
# is not printable ASCII makes this fail instead of writing a file the
# controller would refuse: every value that gets here has been through
# read_answers, so a character outside that set means something unchecked found
# its way in.
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

# UNPAIRED_URL, UNPAIRED_KEY and UNPAIRED_HASH are what the provisional
# controller.json carries where the pairing will put the API and the anchor.
#
# Why there is a provisional file at all, measured on the program and not
# guessed: ngc-controller pair reads its configuration BEFORE it asks for the
# code (node.pair calls config.LoadController first), and config.Validate wants
# at least one API with a key and a TLS fingerprint and an anchor with a
# sequence number that is not zero. The pairing is what brings exactly those
# values - the code carries the address of the API and the anchor - so the file
# it reads cannot already hold them.
#
# What these three are chosen for is that they can never become trust: the
# address is in the reserved domain .invalid, which resolves nowhere, and the
# key, the fingerprint and the hash of the anchor are 32 zero bytes, which no
# node and no version of a trust list has. And the file never reaches
# /etc/ngc: it lies in WORK, which is 0700, root's and removed when the script
# ends, and only the file the pairing wrote is put in place.
UNPAIRED_URL="wss://unpaired.invalid:7443/tunnel"
UNPAIRED_KEY="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
UNPAIRED_HASH="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

# render_controller_json writes controller.json (config.Controller): strict
# JSON, never a null, and an empty field left out entirely
# (shared/README.md) - that is why podman is missing: config.parseController
# fills in /usr/bin/podman, and the path repeated here would be a second place
# to keep right. node is left out as well: only an admin's trust list gives
# this server its node ID, and the pairing clears it.
#
# Every text goes through json_text, which escapes the quote, the backslash and
# the line breaks of the PEM block and refuses anything else, so one
# unprintable character stops the write instead of making a file the controller
# cannot read. Each key stands on a line of its own in the shape kept_key reads
# back.
render_controller_json() {
	local noise="$1" dbkey="$2" release="$3"
	local i last
	printf '{\n'
	printf '  "name": %s,\n' "$(json_text "$NGC_NAME")"
	printf '  "noiseKey": "%s",\n' "$noise"
	printf '  "apis": [\n'
	printf '    {\n'
	printf '      "url": %s,\n' "$(json_text "$UNPAIRED_URL")"
	printf '      "key": "%s",\n' "$UNPAIRED_KEY"
	printf '      "tls": "%s"\n' "$UNPAIRED_KEY"
	printf '    }\n'
	printf '  ],\n'
	printf '  "anchor": {\n'
	printf '    "seq": 1,\n'
	printf '    "hash": "%s"\n' "$UNPAIRED_HASH"
	printf '  },\n'
	printf '  "db": %s,\n' "$(json_text "$NGC_STATE")"
	printf '  "dbKey": "%s",\n' "$dbkey"
	printf '  "releaseKey": "%s",\n' "$release"
	printf '  "roles": ['
	last=$((${#ROLES[@]} - 1))
	for i in "${!ROLES[@]}"; do
		if [ "$i" -lt "$last" ]; then
			printf '%s, ' "$(json_text "${ROLES[$i]}")"
		else
			printf '%s' "$(json_text "${ROLES[$i]}")"
		fi
	done
	printf ']'
	if [ "$HAS_WEB" -eq 1 ]; then
		printf ',\n'
		printf '  "webConfig": %s' "$(json_text "$NGC_WEB_JSON")"
	fi
	if [ "$HAS_DB" -eq 1 ]; then
		printf ',\n'
		printf '  "migrate": {\n'
		printf '    "driver": "mariadb",\n'
		printf '    "nodes": [\n'
		last=$((${#MIG_NODES[@]} - 1))
		for i in "${!MIG_NODES[@]}"; do
			if [ "$i" -lt "$last" ]; then
				printf '      %s,\n' "$(json_text "${MIG_NODES[$i]}")"
			else
				printf '      %s\n' "$(json_text "${MIG_NODES[$i]}")"
			fi
		done
		printf '    ],\n'
		printf '    "name": %s,\n' "$(json_text "$NGC_MIGRATE_NAME")"
		printf '    "user": %s,\n' "$(json_text "$NGC_MIGRATE_USER")"
		printf '    "password": %s,\n' "$(json_text "$NGC_MIGRATE_PASSWORD")"
		printf '    "ca": %s\n' "$(json_text "$CA_PEM")"
		printf '  }'
	fi
	printf '\n}\n'
}

# controller_json_ok says whether every text of the configuration survived
# json_text. $( ) throws away the exit status of what ran inside it, so
# render_controller_json cannot report a refused character by failing - this
# asks every value once more before a file is written. The keys are not asked:
# they come out of valid_b64url_n or out of openssl.
controller_json_ok() {
	local v
	for v in "$NGC_NAME" "$UNPAIRED_URL" "$NGC_STATE" "$NGC_WEB_JSON" \
		"$NGC_MIGRATE_NAME" "$NGC_MIGRATE_USER" "$NGC_MIGRATE_PASSWORD" "$CA_PEM" \
		${ROLES[@]+"${ROLES[@]}"} ${MIG_NODES[@]+"${MIG_NODES[@]}"}; do
		json_text "$v" >/dev/null || return 1
	done
	return 0
}

# write_provisional makes the configuration the pairing reads: a key of this
# server, the key of its data, and everything the answers decided. The key of
# the data is kept where there is one - see kept_key.
write_provisional() {
	local noise dbkey release
	noise="$(random_key 32)"
	dbkey="$(kept_key dbKey 86)" || dbkey="$(random_key 64)"
	release="$(release_key_b64)" ||
		log_error "The release key in this script is no Ed25519 key in PEM form, so controller.json cannot be written. Please get a newer version of ulh."
	controller_json_ok || log_error "One of the answers carries a character that may not stand in controller.json. Nothing was written."
	umask 077
	render_controller_json "$noise" "$dbkey" "$release" >"${WORK}/controller.json" ||
		log_error "controller.json could not be made."
	chmod 0600 -- "${WORK}/controller.json"
}

# ============================================================
# PAIRING
# ============================================================

# pair_controller runs "ngc-controller pair" with the code of the installation.
# The code goes in through the standard input and never into the command line:
# /proc/<pid>/cmdline is readable by every local user without hidepid
# (shared/ulh.md). The configuration ngc-controller writes is the provisional
# one in WORK with the API and the anchor of the pairing in it; only that file
# is put into /etc/ngc.
#
# The output is not caught and not filtered: the two lines ngc-controller
# prints are the fingerprint of this server's key and the anchor out of the
# code, and the admin has to see them to compare them with the shell. Neither
# of the two is the code.
pair_controller() {
	log_section "Pairing this server with NextGenCloud"
	log_warn "Compare the fingerprint and the anchor below with what NextGenCloud shows. If they differ, break this off: something else is answering there."
	ensure_dir "$NGC_ETC" 0755
	if ! printf '%s\n' "$NGC_PAIR_CODE" |
		"${NGC_BIN}/ngc-controller" -config "${WORK}/controller.json" pair; then
		log_error "The pairing did not work (the message of ngc-controller is above). Nothing was written: ${NGC_CONF} is untouched. A pairing code is good once and for a short time, so get a new one in NextGenCloud and run the setup again."
	fi
	if [ ! -s "${WORK}/controller.json" ] || [ ! -s "$NGC_ANCHOR" ]; then
		log_error "ngc-controller came back without writing its configuration or the anchor ${NGC_ANCHOR}. Nothing was changed; get a new pairing code and run the setup again."
	fi
	# The pairing replaced the provisional address of the API, and that is
	# what says it really happened: a file still naming unpaired.invalid would
	# be one the pairing never wrote.
	if grep -q 'unpaired\.invalid' "${WORK}/controller.json"; then
		log_error "The configuration ngc-controller wrote still names no API, so the pairing did not come off. Nothing was changed; get a new pairing code and run the setup again."
	fi
	put_file "${WORK}/controller.json" "$NGC_CONF" 0600
	chmod 0600 -- "$NGC_ANCHOR"
	chown root:root -- "$NGC_ANCHOR"
	ensure_dir "$NGC_STATE_DIR" 0700
	: >"${WORK}/paired"
	put_file "${WORK}/paired" "$NGC_PAIRED" 0600
	log_info "This server is paired."
}

# paired says whether a pairing came off on this server already, so a second
# run of install does not pair again with a code that is long spent.
paired() {
	[ -f "$NGC_PAIRED" ] && [ -f "$NGC_CONF" ]
}

# change_settings writes the roles, webConfig and migrate of the answers into
# the controller.json that is there, and leaves everything the pairing owns
# alone: name, noiseKey, node, apis and anchor. jq does it, because those five
# cannot be made again out of the answers - a fresh key would put this server
# out of every trust list, and a fresh dbKey would leave the data of every app
# unreadable.
#
# jq is asked for a whole file and the file is replaced atomically with mode
# 0600, so no reader ever sees half of it and the key is never for one moment
# readable by anybody else.
change_settings() {
	# The roles go in as a list of texts, the migrate block as one JSON
	# object, and both are built by jq out of values it was handed - nothing
	# of an answer is pasted into the program of jq itself.
	jq --argjson roles "$(roles_json)" \
		--argjson migrate "$(migrate_json)" \
		--arg web "$NGC_WEB_JSON" \
		'.roles = $roles
		 | if $migrate == null then del(.migrate) else .migrate = $migrate end
		 | if ($roles | index("web")) then .webConfig = $web else del(.webConfig) end' \
		<"$NGC_CONF" >"${WORK}/changed.json" ||
		log_error "The settings in ${NGC_CONF} could not be changed. Is the file still the one NGC wrote?"
	if [ ! -s "${WORK}/changed.json" ]; then
		log_error "The new ${NGC_CONF} came out empty. Nothing was changed."
	fi
	chmod 0600 -- "${WORK}/changed.json"
	put_file "${WORK}/changed.json" "$NGC_CONF" 0600
}

# roles_json prints the roles as a JSON list. jq builds it, so a role that is
# not one of the four words read_answers allows could not get in here anyway.
roles_json() {
	local i
	printf '%s\n' "${ROLES[@]}" | jq -R . | jq -s .
}

# migrate_json prints the migrate block of config.DB as JSON, or null where
# this server has no role db.
migrate_json() {
	if [ "$HAS_DB" -eq 0 ]; then
		printf 'null\n'
		return 0
	fi
	printf '%s\n' "${MIG_NODES[@]}" | jq -R . | jq -s \
		--arg name "$NGC_MIGRATE_NAME" --arg user "$NGC_MIGRATE_USER" \
		--arg password "$NGC_MIGRATE_PASSWORD" --arg ca "$CA_PEM" \
		'{driver: "mariadb", nodes: ., name: $name, user: $user, password: $password, ca: $ca}'
}

# ============================================================
# THE SERVICE
# ============================================================

# render_unit writes ngc-controller.service (config.ServiceController).
#
# Restart=on-failure with RestartSec=5 is not decoration, and it is the one
# place where it belongs (docs/vertraege-v1.2.md, point 32, decided
# 12.10.2026): a controller that cannot get the migration lock of its own
# store does NOT start, on purpose - state.Open does not wait, because a
# service that "runs" and does nothing for up to 900 seconds is worse for an
# admin than one that fails with a line naming the reason. The common case is
# an overlapping restart, and the lock falls as soon as the other run is
# finished, not after its 900 seconds - so the distance is a few seconds and
# NOT anywhere near the lock time. Five seconds also keeps the unit out of
# systemd's own start limit (5 starts in 10 seconds by default): five restarts
# at this distance take 25 seconds.
#
# What this unit does NOT do is take rights away the way ngc-api.service does.
# The controller makes system accounts, mounts encrypted data folders and
# starts containers through podman; ProtectSystem=strict, NoNewPrivileges or
# RestrictNamespaces would each stop one of those, and a sandbox with holes in
# it for all three would say "sandbox" and mean nothing. It runs as root, and
# that is written here so that nobody has to work it out from the file.
render_unit() {
	printf '%s\n' \
		'# /etc/systemd/system/ngc-controller.service' \
		'# Written by ngc-controller.sh of ulh (install, configure). Never edit by hand.' \
		'[Unit]' \
		'Description=NextGenCloud Controller' \
		'Documentation=https://github.com/sorglos-it/nextgencloud' \
		'After=network-online.target' \
		'Wants=network-online.target' \
		'' \
		'[Service]' \
		'Type=simple' \
		"ExecStart=${NGC_BIN}/ngc-controller -config ${NGC_CONF}" \
		'# A controller that cannot get the migration lock of its own store does' \
		'# not start, and the restart is the job of this service file: a few' \
		'# seconds, because the lock falls when the other run is finished.' \
		'Restart=on-failure' \
		'RestartSec=5' \
		'# It runs as root: system accounts, encrypted data folders, containers.' \
		'User=root' \
		'# /run/ngc, where the controller keeps what one run needs.' \
		'RuntimeDirectory=ngc' \
		'RuntimeDirectoryMode=0700' \
		'# The cgroup of this unit is handed to it, and the controller puts' \
		'# itself one level below the root of it. Both lines are needed' \
		'# before an app container can have a limit at all, and each for' \
		'# its own reason (shared/ulh.md of nextgencloud says it in full):' \
		'#   Delegate=yes       - without it the subtree belongs to systemd' \
		'#                        and not even root may make a cgroup in it.' \
		'#   DelegateSubgroup=  - without it the unit holds processes right' \
		'#                        in the root of the subtree, and cgroup v2' \
		'#                        refuses to switch controllers on for the' \
		'#                        children of a cgroup that does - so an app' \
		'#                        cgroup would never get pids.max at all.' \
		'# Measured 24./25.10.2026 on three nodes: no app container had a' \
		'# cgroup of its own, so --pids-limit, --memory and --cpus were' \
		'# given to podman and enforced by nothing.' \
		'Delegate=yes' \
		'DelegateSubgroup=supervisor' \
		'' \
		'[Install]' \
		'WantedBy=multi-user.target'
}

# service_apply starts the controller, and restarts it only when something
# changed: a running controller holds the tunnels to every API and the channels
# of every app, so it is not restarted for nothing (shared/ulh.md: a second run
# changes nothing that is right).
service_apply() {
	systemctl daemon-reload || log_error "systemd did not take the new service file."
	if ! systemctl is-active --quiet "$UNIT_NAME"; then
		systemctl enable --now "$UNIT_NAME" ||
			log_error "The service ${UNIT_NAME} could not be started. 'journalctl -u ${UNIT_NAME}' says why."
		log_info "The controller is running, and from now on it starts with the server."
		return 0
	fi
	if [ "$CHANGED" -eq 0 ]; then
		log_info "Nothing changed, the controller keeps running as it is."
		return 0
	fi
	systemctl restart "$UNIT_NAME" ||
		log_error "The service ${UNIT_NAME} could not be restarted. 'journalctl -u ${UNIT_NAME}' says why."
	log_info "The controller has taken the new settings."
}

# ============================================================
# THE ACTIONS
# ============================================================

install_ngc_controller() {
	need_root
	need_debian
	work_init
	log_section "Setting up the NGC controller on ${NGC_NAME}"
	read_answers
	ensure_packages
	install_release
	ensure_dir "$NGC_ETC" 0755
	ensure_dir "$NGC_DATA" 0755
	ensure_dir "$NGC_STATE_DIR" 0700
	if paired; then
		log_info "This server is paired already, so the pairing is left alone."
		change_settings
	else
		if [ -z "$NGC_PAIR_CODE" ]; then
			log_error "This server is not paired yet, so the setup needs a pairing code. Sign in to NextGenCloud as an administrator, add this server there, and give the code it shows as the answer pair_code."
		fi
		write_provisional
		pair_controller
	fi
	render_unit >"${WORK}/ngc-controller.service"
	put_file "${WORK}/ngc-controller.service" "$UNIT_FILE" 0644
	service_apply
	show_next_steps
}

configure_ngc_controller() {
	need_root
	need_debian
	work_init
	log_section "Changing the settings of the NGC controller"
	read_answers
	if [ ! -x "${NGC_BIN}/ngc-controller" ]; then
		log_error "There is no controller in ${NGC_BIN} yet. Call 'Set up the controller' first."
	fi
	ensure_packages
	ensure_dir "$NGC_ETC" 0755
	ensure_dir "$NGC_STATE_DIR" 0700
	if [ -n "$NGC_PAIR_CODE" ]; then
		# A new code means a new pairing: ngc-controller makes a new key, so
		# this server leaves every trust list and an admin has to enter it
		# again. The key of the data is kept (kept_key), so no app loses its
		# data over it.
		write_provisional
		pair_controller
	elif paired; then
		change_settings
	else
		log_error "This server is not paired yet. Give a pairing code out of NextGenCloud as the answer pair_code, or call 'Set up the controller'."
	fi
	render_unit >"${WORK}/ngc-controller.service"
	put_file "${WORK}/ngc-controller.service" "$UNIT_FILE" 0644
	service_apply
	show_next_steps
}

uninstall_ngc_controller() {
	local f
	need_root
	need_debian
	work_init
	log_section "Removing the NGC controller"

	systemctl disable --now "$UNIT_NAME" >/dev/null 2>&1 || true
	rm -f -- "$UNIT_FILE"
	systemctl daemon-reload || true
	rm -f -- "${NGC_BIN}/ngc-controller"
	log_info "The service and the program in ${NGC_BIN} are gone."

	# Only the files of the controller, never the whole /etc/ngc: on a server
	# with several roles api.json and web.json lie there too and belong to
	# other parts. /var/lib/ngc/release.seq counts for every part, so it stays
	# as well. trust-anchor.json is the controller's own (it is what writes
	# it), so it goes with the controller.
	if [ "$NGC_PURGE" = yes ]; then
		# The warning comes BEFORE the deletion. After it, it is a log entry
		# and no warning: dbKey in controller.json is what the data of every
		# app on this server is encrypted with, and there is no second copy of
		# it anywhere.
		log_warn "Now removing ${NGC_CONF}, the anchor and the data of the apps under ${NGC_DATA}/apps. The key dbKey in controller.json is what that data is encrypted with; once it is gone, nothing opens it again. Put the file away first if you are not sure."
		for f in "$NGC_CONF" "$NGC_ANCHOR"; do
			rm -f -- "$f"
		done
		rm -rf -- "${NGC_STATE_DIR:?}" "${NGC_KEPT:?}" "${NGC_DATA:?}/apps"
		log_warn "Deleted: controller.json, the anchor, the local store and the data of the apps."
	else
		# Kept data stays under /var/lib/ngc/, so a new installation finds it
		# again (shared/ulh.md). 0700 and root's: controller.json holds keys.
		ensure_dir "$NGC_KEPT" 0700
		for f in "$NGC_CONF" "$NGC_ANCHOR"; do
			if [ -f "$f" ]; then
				cp -p -- "$f" "${NGC_KEPT}/"
			fi
		done
		log_info "Kept: controller.json and the anchor stay in ${NGC_ETC}, with a copy of them under ${NGC_KEPT}; the local store and the data of the apps stay under ${NGC_DATA}."
	fi
	log_info "Done."
}

# show_next_steps says what the rest of the installation waits for. The
# fingerprint and the anchor are not printed again here: ngc-controller printed
# them during the pairing, and a second copy out of a file would be one this
# script computed instead of the program that holds the key.
show_next_steps() {
	printf '\n'
	log_info "Done. What comes next:"
	printf '\n'
	printf '  Sign in to NextGenCloud as an administrator and enter this server\n'
	printf '  (%s) in the trust list. Until then it takes no tasks: a pairing\n' "$NGC_NAME"
	printf '  makes a new key, so it stands in no list of its own accord.\n'
	if [ "$HAS_WEB" -eq 1 ]; then
		printf '\n'
		printf '  This server carries the web interface, so set it up with ngc-web\n'
		printf '  as well. From then on the controller keeps the list of the APIs\n'
		printf '  in %s and in the Apache file by itself.\n' "$NGC_WEB_JSON"
	fi
	if [ "$HAS_DB" -eq 1 ]; then
		printf '\n'
		printf '  This server carries the role db, so NextGenCloud may choose it to\n'
		printf '  play in the migrations of an update. Nothing more to do for that.\n'
	fi
	printf '\n'
	printf '  How it is doing: systemctl status %s\n' "$UNIT_NAME"
}

# ============================================================
# MAIN
# ============================================================

case "$ACTION" in
install)
	install_ngc_controller
	;;
configure | config)
	configure_ngc_controller
	;;
uninstall)
	uninstall_ngc_controller
	;;
*)
	# Prints the actions and their parameters from the catalog.
	print_usage ngc-controller && exit 1
	;;
esac

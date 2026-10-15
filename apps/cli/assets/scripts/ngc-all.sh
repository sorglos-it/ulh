#!/bin/bash

# ngc-all - NextGenCloud on ONE machine (Debian and Ubuntu, a Pi among them).
#
# What it does: the programs ngc-api, ngc-store and ngc-controller into
# /usr/lib/ngc/, /etc/ngc/api.json against an encrypted SQLite FILE instead of
# MariaDB, the service ngc-api.service, the setup code of the first admin
# account - and after the first setup, with a pairing code out of the browser,
# /etc/ngc/controller.json and ngc-controller.service. Contract: shared/ulh.md
# of the NGC repository (github.com/sorglos-it/nextgencloud), rules "ngc-all",
# "Hosts und Adressen", "TLS intern, nie ungeprueft", "Schluessel erzeugt
# immer der Server selbst" and the release check of
# shared/testdata/release/verify.sh.
#
# The prompts of assets/catalog.yaml carry the answers of that contract, in
# this order (ulh joins them with commas, so no answer may hold a comma):
#   1  name       NGC_NAME       name of this machine and of its API (wire.ValidName)
#   2  hostname   NGC_HOSTNAME   name or IPv4 address the browser reaches it by
#   3  store_url  NGC_STORE_URL  the app store, empty for the official one
#   4  store_key  NGC_STORE_KEY  its public key, empty for the official one
#   5  pair_code  NGC_PAIR_CODE  configure: the pairing code out of the browser
#
# ============================================================
# WHAT THIS SCRIPT DOES DIFFERENTLY FROM ITS TWO SIBLINGS
# ============================================================
#
# 1. SQLITE INSTEAD OF MARIADB. ngc-api.sh refuses every driver but mariadb and
#    says in its own message that one machine on SQLite is this script's
#    business. Here the database is a FILE (config.DB.Path), encrypted whole
#    with AES-256-XTS, and its key is 64 bytes (config.DB.Key, 86 characters of
#    base64url). config.DB.Validate refuses Nodes, Name, User, Password and CA
#    next to a SQLite path, so none of them is asked and none is written.
#
# 2. IT PAIRS THE CONTROLLER ITSELF. ngc-controller pair reads its
#    configuration BEFORE it asks for the code (node.pair calls
#    config.LoadController first), and config.Validate wants an API with a key
#    and a TLS fingerprint and an anchor whose number is not zero - which is
#    exactly what the pairing brings. So the file it reads is a PROVISIONAL one
#    in a mktemp -d (0700, file 0600), with wss://unpaired.invalid:7443/tunnel
#    and 32 zero bytes where the trust will go; /etc/ngc never sees it. After
#    the pairing this script checks that unpaired.invalid is GONE out of the
#    file ngc-controller wrote, and only then does the file go to its place.
#    Same way as ngc-controller.sh; measured against the program on 13.10.2026
#    (NGC docs/vertraege-v1.2.md, point 44: pair gets as far as the question
#    for the code, a wrong code gives exit 2, /etc/ngc stays untouched).
#
# 3. TWO PROGRAMS, ONE MACHINE - AND NOT ONE FILE. This is the point of this
#    script, so it is written out here and not only in a function:
#
#    - On SQLite EVERY caller of Open migrates at its own start (sqlite.Open of
#      apps/server-db: "on SQLite EVERY caller of this function migrates").
#      With MariaDB one controller with the role db runs them for all.
#    - What keeps two callers apart is the migration lock ngc_lock - and it
#      does so only for the MOMENT of a migration: the runner deletes its row
#      at the end (migrate.go, freeLock). Measured on the running programs on
#      13.10.2026 (point 44): a second ngc-api on the same file comes THROUGH
#      dbopen.Open and dies at the port, and ngc-api migrate runs while an API
#      holds the same file open. So the lock does NOT keep two programs apart.
#    - Therefore this script gives each program its OWN file with its OWN key:
#      the API gets /var/lib/ngc/api/ngc.db, the controller
#      /var/lib/ngc/controller/state.db. The two paths are constants here, and
#      check_two_files refuses to write anything if they are ever the same.
#    - The one place where one file really has two readers stays, and it is the
#      contract's: with the role db the controller carries the access for the
#      migrations of an UPDATE, and on this machine that access is the API's
#      file and the API's key (shared/ulh.md: "auf dem Pi: SQLite-Datei und
#      Schluessel"). What this script does about it is the only thing a script
#      can do: ngc-controller.service is ordered AFTER ngc-api.service, so at
#      every start exactly one of the two migrates first, and both carry
#      Restart=on-failure with RestartSec=5, so whoever meets the lock comes
#      back a few seconds later instead of forcing its way in.
#    - NOT MEASURED, and named here instead of promised away: what a REAL
#      migration of an update does while the API holds the file. The one
#      measurement there is ran with nothing to migrate ("0 Migrationen
#      eingespielt.", exit 0). Whoever has a machine measures it.
#
# 4. THE TRUST ANCHOR GIVES NO PROTECTION HERE, and that is written down
#    instead of promised (NGC docs/vertraege-v1.2.md, point 43). The anchor
#    protects against someone who can write the DATABASE but holds no admin
#    key: he must not turn the trust list back. On this machine the database IS
#    a file in /var/lib/ngc, owned by root, and /etc/ngc/trust-anchor.json is a
#    file in the same hand - so whoever can write the one can delete the other.
#    On one machine the anchor is a safeguard against a MISTAKE, not against an
#    attacker who is already root. Nothing in this script says otherwise.
#
# WHAT THIS SCRIPT DOES NOT DO, named so that nobody looks for it:
#
#   - The web interface. Apache, PHP, the certificate (cert_mode) and
#     /etc/ngc/web.json are ngc-web's work, and shared/ulh.md lists cert_mode
#     among ngc-all's answers because ngc-all was meant to carry that half too.
#     It does not carry it: there is no second implementation of a vhost, a
#     certificate and a balancer file in ulh, and a copy of one would be a
#     second place to keep right. So this script asks no cert_mode, writes no
#     web.json, and says at the end that ngc-web is the next step. The
#     fingerprint it prints is what ngc-web asks for.
#   - It makes no key of the TLS kind and no key for the trust list: ngc-api
#     makes its certificate itself at its first start, and ngc-controller makes
#     the Noise key of this machine during the pairing.
#   - It shows no pairing code and writes none into a log.
#
# Everything this script prints is English, as in every other ulh script. The
# five languages of ulh sit in assets/catalog.yaml.

set -eu
source "$(dirname "$0")/../../classes/bootstrap.sh"
# The script itself decides when the parameters get parsed:
parse_parameters "${1:-}"

# The character ranges below are the C ranges, whatever locale the admin runs:
# in another one [a-z] and grep's classes take further letters, and a host that
# slipped through would end up in api.json and in the certificate of this
# machine (shared/ulh.md, "Hosts und Adressen"; the same check as
# shared/testdata/ulh/host.sh).
LC_ALL=C
export LC_ALL

# ============================================================
# WHERE EVERYTHING LIVES (package config of the NGC contract)
# ============================================================

NGC_ETC="/etc/ngc"                              # config.Dir
NGC_TLS="/etc/ngc/tls"
NGC_API_JSON="/etc/ngc/api.json"                # config.APIFile
NGC_CONF="/etc/ngc/controller.json"             # config.ControllerFile
NGC_ANCHOR="/etc/ngc/trust-anchor.json"         # config.AnchorFile
NGC_WEB_JSON="/etc/ngc/web.json"                # config.WebFile, ngc-web writes it
NGC_CERT="/etc/ngc/tls/api.crt"                 # made by ngc-api itself
NGC_KEY="/etc/ngc/tls/api.key"
NGC_BIN="/usr/lib/ngc"                          # config.BinDir
NGC_DATA="/var/lib/ngc"                         # config.DataDir
NGC_SEQ="/var/lib/ngc/release.seq"              # the release installed last
NGC_STAGE="/var/lib/ngc/staged"                 # config.StageDir: release files by hand
NGC_SETUP_CODE="/var/lib/ngc/setup-code"        # written by ngc-api, read by root only
NGC_API_DB_DIR="/var/lib/ngc/api"               # the API's own folder
NGC_API_DB="/var/lib/ngc/api/ngc.db"            # config.API.DB.Path - the API's file
NGC_STATE_DIR="/var/lib/ngc/controller"         # the controller's own folder
NGC_STATE="/var/lib/ngc/controller/state.db"    # config.Controller.DB - its own file
NGC_PAIRED="/var/lib/ngc/controller/paired"     # set once a pairing came off
NGC_KEPT="/var/lib/ngc/all-kept"                # uninstall keeps the configuration here
UNIT_API="/etc/systemd/system/ngc-api.service"
UNIT_CTRL="/etc/systemd/system/ngc-controller.service"
NAME_API="ngc-api.service"                      # config.ServiceAPI
NAME_CTRL="ngc-controller.service"              # config.ServiceController
API_PORT=7443                                   # config.APIPort
PODMAN="/usr/bin/podman"                        # config.DefaultPodman

# The four roles of this machine. It is every role there is, because everything
# runs here (shared/ulh.md, "ngc-all": alle vier Rollen). The order is the one
# tunnel.Components lists them in.
ROLES=(web api db services)

# Packages: openssl and jq for the check of the program files, curl to fetch
# them, ca-certificates so that the release server can be reached at all, and
# podman because this machine carries the services as well.
NGC_PACKAGES=(openssl jq curl ca-certificates podman)

# Where the release files come from. The address carries no trust at all: the
# signature of release.json and the SHA-256 of the file do (verify_release), so
# a mirror, NGC_RELEASE_BASE or a copy in /var/lib/ngc/staged is exactly as
# safe as this one.
NGC_RELEASE_BASE="${NGC_RELEASE_BASE:-https://github.com/sorglos-it/nextgencloud/releases/latest/download}"

# The public key of NGC's releases (sign.PurposeRelease), fixed in the script.
# It is the whole trust in a release, and it goes into api.json and
# controller.json as releaseKey so that both judge an update by the same key.
# The placeholder below is not a key, so every install stops at the check -
# which is the safe way round until the real key is in here.
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
NGC_NAME="${NGC_NAME:-}"
NGC_HOSTNAME="${NGC_HOSTNAME:-}"
NGC_STORE_URL="${NGC_STORE_URL:-}"
NGC_STORE_KEY="${NGC_STORE_KEY:-}"
NGC_PAIR_CODE="${NGC_PAIR_CODE:-}"
NGC_PURGE="${NGC_PURGE:-no}"

TUNNEL_URL=""     # wss://<hostname>:7443/tunnel, what api.json calls url
STORE_URL=""      # the store that is really written
STORE_KEY=""      # and its key
RELEASE_NAME=""   # the file of the part being installed
RELEASE_ARCH=""   # amd64 or arm64, from dpkg
CHANGED_API=0     # something of the API was written: its service needs a restart
CHANGED_CTRL=0    # the same for the controller
WORK=""           # temporary directory, removed on exit

# ============================================================
# SMALL HELPERS
# ============================================================

# work_init makes the temporary directory and has it removed again, whatever
# ends the script. It matters twice over here: the provisional controller.json
# that goes into "ngc-controller pair" lies in it, and so does the 64 byte key
# the whole database of this machine is encrypted with. 0700 and root's, so
# neither is for one moment readable by anybody else. The :? in the trap is not
# decoration: an empty WORK would turn that line into a removal of the root
# directory.
work_init() {
	if [ -n "$WORK" ]; then
		return 0
	fi
	WORK="$(mktemp -d)"
	chmod 0700 -- "$WORK"
	# shellcheck disable=SC2064
	trap "rm -rf -- \"\${WORK:?}\"" EXIT
	trap 'exit 1' HUP INT TERM
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
		log_error "NGC sets up a single machine on Debian and Ubuntu only. Found: ${OS_DISTRO}."
	fi
}

# check_two_files is the guard of point 3 in the head of this script: the API
# and the controller never get the same file. They are two constants, so this
# can only ever fail after somebody edits them - which is exactly when it has
# to fail, because the lock ngc_lock would not keep the two programs apart.
check_two_files() {
	if [ "$NGC_API_DB" = "$NGC_STATE" ]; then
		log_error "The API and the controller are set to the same database file (${NGC_API_DB}). On SQLite every program migrates at its own start and the migration lock does not keep two programs apart, so this script does not write anything. Give each of the two its own file."
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
# trust.ValidHostPort does. It is here for the store address, which may carry a
# port; no database node is asked for on this machine.
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
# hyphens, at most 32 characters. On this machine it is BOTH names at once: the
# node of the API in the trust list (config.API.Node) and the name of the
# machine the controller carries (config.Controller.Name). One machine, one
# name - and one answer less to get wrong.
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

# valid_b64url_n: n characters of base64url without padding. 43 characters are
# the 32 bytes of every Secret of api.json and of releaseKey and storeKey, 86
# the 64 bytes of the SQLite keys - config.DB.Key and config.Controller.DBKey,
# two AES-256 keys for AES-256-XTS (enc.Bytes, config.Secret).
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
# form every key takes in api.json and controller.json (enc.Bytes,
# config.Secret).
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
# Nothing unchecked may reach api.json, controller.json, a service file or a
# command line. There is no database answer at all on this machine: the file
# and its key are this script's, and config.DB.Validate refuses a name, an
# account, a password, a CA or a node next to a SQLite path.
read_answers() {
	if ! valid_name "$NGC_NAME"; then
		log_error "This name of the machine is not allowed: '${NGC_NAME}'. Take a lower case letter first, then letters, digits and hyphens, at most 32 characters - for example ngc. It is the name of this machine and of its API at once."
	fi
	if ! valid_host "$NGC_HOSTNAME"; then
		log_error "This address of the machine is not allowed: '${NGC_HOSTNAME}'. Take a name in lower case (for example ngc.example.org) or an IPv4 address (for example 192.168.1.20). No IPv6, and nothing with https:// in front."
	fi
	TUNNEL_URL="wss://${NGC_HOSTNAME}:${API_PORT}/tunnel"

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

	if [ -n "$NGC_PAIR_CODE" ] && ! valid_pair_code "$NGC_PAIR_CODE"; then
		log_error "This is no pairing code. It starts with ngc-pair: and the web interface of this machine shows it once you have signed in with the setup code. Please insert the code completely."
	fi
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
# of install changes nothing that is already right, and a service is restarted
# only when something really changed (shared/ulh.md). The new file is written
# next to the old one and renamed, so a reader never sees half a file, and its
# mode is set before a single byte is in it: both configurations carry keys,
# and a chmod after the write leaves exactly the window open in which they are
# readable.
#
# $4 says whose restart this file is: "api", "ctrl" or "both". A file of the
# controller must not restart the API, which would drop every open session for
# nothing.
put_file() {
	local src="$1" dst="$2" mode="$3" whose="${4:-both}" tmp
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
	case "$whose" in
	api) CHANGED_API=1 ;;
	ctrl) CHANGED_CTRL=1 ;;
	*)
		CHANGED_API=1
		CHANGED_CTRL=1
		;;
	esac
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
# On a Pi that answer is arm64, and a 32 bit Raspberry Pi OS says armhf -
# refused here rather than later, by a file that will not run.
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

# release_file prints the file name of part $1 for this architecture: the last
# segment of the entry's url, and only if it is a name and not a path (the same
# rule as verify.sh, which checks it again). This machine installs TWO parts,
# so the part is an argument here and not a constant as in its siblings.
release_file() {
	local url name
	url="$(jq -er --arg part "$1" --arg arch "$RELEASE_ARCH" '[.files[]? | select(.part == $part and .arch == $arch)]
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

# verify_release checks the release in directory $1 for part $2 the way
# shared/ulh.md prescribes and shared/testdata/release/verify.sh shows: the
# signature of release.json over "ngc/release/v1", a NUL byte and the payload,
# then the one entry for that part and this architecture with its file name,
# SHA-256 and size. It writes nothing into the directory and says "release
# wrong: <reason>" when something is off.
verify_release() {
	(
		set -eu
		cd -- "$1"
		part="$2"
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
		jq -r --arg part "$part" --arg arch "$RELEASE_ARCH" '
			if (.files | type) != "array" then error("files is not a list") else . end
			| [.files[] | select(.part == $part and .arch == $arch)]
			| if length != 1 then error("not exactly one entry") else .[0] end
			| if (.url | type) == "string" and (.sha256 | type) == "string" and (.size | type) == "number"
			then [.url, .sha256, (.size | tostring)] | @tsv else error("entry of wrong types") end
		' "$WORK/v.payload.json" >"$WORK/v.entry.tsv" || fail "no single valid entry for ${part} ${RELEASE_ARCH}"
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

# fetch_release puts release.json and the one file of part $2 into directory $1
# and leaves its name in RELEASE_NAME. /var/lib/ngc/staged is taken as it is
# when it already holds a release.json, so an installation without internet
# works with a copy put there by hand - which on a Pi behind a slow line is the
# usual way round.
fetch_release() {
	local dir="$1" part="$2"
	RELEASE_NAME=""
	if [ -f "${NGC_STAGE}/release.json" ]; then
		log_info "Using the release files from ${NGC_STAGE}."
		cp -f -- "${NGC_STAGE}/release.json" "${dir}/release.json"
		if ! release_payload "$dir"; then
			log_error "The file ${NGC_STAGE}/release.json is damaged."
		fi
		RELEASE_NAME="$(release_file "$part")" || log_error "There is no entry for ${part} ${RELEASE_ARCH} in ${NGC_STAGE}/release.json."
		if [ ! -f "${NGC_STAGE}/${RELEASE_NAME}" ]; then
			log_error "The file ${RELEASE_NAME} is missing in ${NGC_STAGE}."
		fi
		cp -f -- "${NGC_STAGE}/${RELEASE_NAME}" "${dir}/${RELEASE_NAME}"
		return 0
	fi

	log_info "Loading the program files of ${part} from ${NGC_RELEASE_BASE} ..."
	if ! download "${NGC_RELEASE_BASE}/release.json" "${dir}/release.json"; then
		return 1
	fi
	if ! release_payload "$dir"; then
		log_error "The release.json that arrived is damaged. Try again later."
	fi
	# Only the name comes out of the payload, never the address: so a tampered
	# release.json cannot point the download anywhere else, and the signature
	# check right after decides everything else.
	RELEASE_NAME="$(release_file "$part")" || log_error "There is no entry for ${part} ${RELEASE_ARCH} in release.json. That file does not belong to this script."
	download "${NGC_RELEASE_BASE}/${RELEASE_NAME}" "${dir}/${RELEASE_NAME}"
}

# download fetches one file over HTTPS and nothing else: no other protocol, not
# even after a redirect, and never more than 256 MB.
download() {
	curl --proto '=https' --proto-redir '=https' --tlsv1.2 --location \
		--fail --silent --show-error --max-time 600 --max-filesize 268435456 \
		--output "$2" -- "$1"
}

# programs_here says whether all three programs of this machine are installed.
programs_here() {
	[ -x "${NGC_BIN}/ngc-api" ] && [ -x "${NGC_BIN}/ngc-store" ] &&
		[ -x "${NGC_BIN}/ngc-controller" ]
}

# part_programs prints the names the archive of part $1 carries. The release of
# ngc-api carries two programs, that of ngc-controller one.
part_programs() {
	case "$1" in
	ngc-api) printf '%s\n' ngc-api ngc-store ;;
	ngc-controller) printf '%s\n' ngc-controller ;;
	*) return 1 ;;
	esac
}

# install_release installs both parts of this machine: ngc-api (which carries
# ngc-api and ngc-store in one archive, the migrations inside ngc-api) and
# ngc-controller. The number of the release is written once, at the end, and
# only when BOTH parts are in: /var/lib/ngc/release.seq counts for every part,
# so a half installation must not leave a number behind that says it is done.
install_release() {
	local dir seq have part
	case "$NGC_RELEASE_KEY" in
	*REPLACE-THIS-LINE*)
		log_error "This script has no real release key of NGC yet. Without it nobody can check whether the program files are genuine, so the setup stops here. Please get a newer version of ulh."
		;;
	esac
	RELEASE_ARCH="$(release_arch)" ||
		log_error "NGC builds its programs for amd64 and arm64. This system is neither of the two, so there is no file for it. On a Raspberry Pi that means the 64 bit system: a 32 bit Raspberry Pi OS says armhf and has no file here."

	have=0
	if [ -f "$NGC_SEQ" ]; then
		have="$(head -n 1 -- "$NGC_SEQ" | tr -dc '0-9')"
		have="${have:-0}"
	fi

	seq=""
	for part in ngc-api ngc-controller; do
		dir="${WORK}/release-${part}"
		rm -rf -- "$dir"
		mkdir -p -- "$dir"
		if ! fetch_release "$dir" "$part"; then
			if programs_here && [ -f "$NGC_SEQ" ]; then
				log_warn "The program files could not be loaded. It stays with the programs in ${NGC_BIN}, which were checked before."
				return 0
			fi
			log_error "The program files could not be loaded. Check the internet connection, or put release.json and the files of ngc-api and ngc-controller into ${NGC_STAGE} by hand. As long as NGC has published no release, that folder is the only way that works."
		fi
		if ! verify_release "$dir" "$part"; then
			log_error "The program files of ${part} are not signed by NGC (the reason is above). Nothing is installed. Get ulh again and try once more; if it stays that way, report it at github.com/sorglos-it/ulh/issues."
		fi
		log_info "The signature of the program files of ${part} is good."

		# Never a release older than the one installed; the same number may
		# come again to repair an installation (shared/ulh.md). The number is
		# read out of the payload verify_release has just confirmed, not out of
		# the one that was decoded before the signature was checked.
		seq="$(jq -er '.seq | numbers' <"$WORK/v.payload.json")" || log_error "The number of the release is missing in release.json."
		case "$seq" in
		'' | *[!0-9]*) log_error "The number of the release is not a number." ;;
		esac
		if [ "$seq" -lt "$have" ]; then
			log_error "The release ${seq} that arrived is older than the installed ${have}. A step backwards is not installed."
		fi
		if [ "$seq" -eq "$have" ] && programs_here; then
			log_info "The programs are here in this version already (release ${seq})."
			return 0
		fi
		unpack_release "${dir}/${RELEASE_NAME}" "$part"
	done

	ensure_dir "$NGC_DATA" 0755
	printf '%s\n' "$seq" >"${WORK}/seq"
	put_file "${WORK}/seq" "$NGC_SEQ" 0644 both
}

# unpack_release takes the programs of part $2 out of the checked archive. Safe
# unpacking of NGC (shared/README.md): no absolute path, no "..", no links, no
# device files - and here nothing but the names this part carries, so a file
# that wants to land anywhere else is never written at all.
unpack_release() {
	local tarball="$1" part="$2" entry p ok
	local -a want=()
	mapfile -t want < <(part_programs "$part")
	if [ "${#want[@]}" -eq 0 ]; then
		log_error "This script knows no part ${part}."
	fi
	if ! tar -tf "$tarball" >"${WORK}/entries" 2>/dev/null; then
		log_error "The file that arrived is no archive that can be read. The release of ${part} carries ${want[*]} in one archive."
	fi
	while IFS= read -r entry; do
		ok=0
		for p in "${want[@]}"; do
			if [ "$entry" = "$p" ] || [ "$entry" = "./${p}" ]; then
				ok=1
			fi
		done
		if [ "$ok" -eq 0 ]; then
			log_error "The archive holds ${entry}, and the release of ${part} carries nothing but ${want[*]}. Nothing is unpacked."
		fi
	done <"${WORK}/entries"
	# Only plain files: the first letter of tar's long listing is the kind, so
	# d, l (link), h (hard link), b, c, p and s are all refused.
	if tar -tvf "$tarball" 2>/dev/null | grep -qv '^-'; then
		log_error "The archive holds a folder, a link or a device file. Nothing is unpacked."
	fi

	rm -rf -- "${WORK}/bin-${part}"
	mkdir -p -- "${WORK}/bin-${part}"
	tar -xf "$tarball" -C "${WORK}/bin-${part}" --no-same-owner --no-same-permissions ||
		log_error "The archive could not be unpacked."
	for p in "${want[@]}"; do
		if [ ! -f "${WORK}/bin-${part}/${p}" ]; then
			log_error "${p} is missing in the archive of ${part}. It does not belong to this script."
		fi
	done
	ensure_dir "$NGC_BIN" 0755
	for p in "${want[@]}"; do
		# 0755 and root's: both programs run as root - the API binds port 7443,
		# the controller makes system accounts and starts containers - and
		# nobody else may change what they run.
		case "$p" in
		ngc-controller) put_file "${WORK}/bin-${part}/${p}" "${NGC_BIN}/${p}" 0755 ctrl ;;
		*) put_file "${WORK}/bin-${part}/${p}" "${NGC_BIN}/${p}" 0755 api ;;
		esac
	done
	log_info "The programs of ${part} are in ${NGC_BIN}."
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
		log_info "Everything this machine needs is installed already."
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
	# This machine carries every role, the services among them, and the
	# controller starts podman by its path out of controller.json
	# (config.Controller.Podman, default /usr/bin/podman). A podman somewhere
	# else would start no container at all, and the admin would hunt the app
	# and not the path.
	if [ ! -x "$PODMAN" ]; then
		log_error "This machine carries the services, so it needs podman at ${PODMAN}, and there is none. Install the package podman and run the setup again."
	fi
}

# ============================================================
# KEYS AND JSON
# ============================================================

# random_key prints n random bytes as base64url, the form every key of the two
# configurations takes. The bytes come from the kernel through openssl, and
# they go through a file in WORK (0700 and root's) so that no key ever stands
# in the argument list of a command, where every other process could read it.
random_key() {
	openssl rand -out "${WORK}/key.bin" "$1" || log_error "No random bytes could be made."
	b64url_of_file "${WORK}/key.bin"
	rm -f -- "${WORK}/key.bin"
}

# release_key_b64 prints the release key of this script as the 32 bytes the
# configurations carry (config.API.ReleaseKey, config.Controller.ReleaseKey):
# an Ed25519 public key in DER is a 12 byte header and the key, so the last 32
# bytes of 44 are the key itself.
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

# kept_key prints the key named $2 out of the file $1, or nothing; $3 is how
# many characters it has to have. The keys of a machine that is already set up
# are KEPT, every one of them, and each for its own reason:
#
#   - noiseKey and signKey are what this API is in the trust list,
#   - secretKey opens every secret in the database,
#   - challengeKey decides the made-up answer for a login name no user has,
#   - and the two SQLite keys are what the whole database of this machine is
#     encrypted with. There is no second copy of either anywhere, so a fresh
#     one would leave the data unreadable - on one machine that is everything
#     there is.
#
# The line is read with sed and not with jq, so this works in the one case that
# matters most - a repair run on a machine where something is broken - and the
# answer is checked by valid_b64url_n afterwards, so only base64url of the
# right length ever comes back. The render functions write one key per line in
# exactly this shape, so there is no second shape to read.
kept_key() {
	local k
	if [ ! -f "$1" ]; then
		return 1
	fi
	k="$(sed -n "s/^  \"$2\": \"\([A-Za-z0-9_-]*\)\",\{0,1\}\$/\1/p" <"$1" | head -n 1)"
	valid_b64url_n "$3" "$k" || return 1
	printf '%s\n' "$k"
}

# kept_db_key prints the 64 byte key of the API's SQLite file out of api.json.
# It needs a reader of its own because that key does NOT stand at the top
# level: it is a field of the db object, indented by four spaces
# (render_api_json writes it on a line of its own in exactly this shape).
kept_db_key() {
	local k
	if [ ! -f "$NGC_API_JSON" ]; then
		return 1
	fi
	k="$(sed -n 's/^    "key": "\([A-Za-z0-9_-]*\)",\{0,1\}$/\1/p' <"$NGC_API_JSON" | head -n 1)"
	valid_b64url_64 "$k" || return 1
	printf '%s\n' "$k"
}

# json_text prints a text as a JSON string, with the quotes around it. Only the
# three characters that a JSON string may not carry raw are escaped -
# backslash, quote and a line break - and anything else that is not printable
# ASCII makes this fail instead of writing a file a program would refuse: every
# value that gets here has been through read_answers, so a character outside
# that set means something unchecked found its way in.
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

# ============================================================
# api.json
# ============================================================

# render_api_json writes /etc/ngc/api.json (config.API) for ONE machine: strict
# JSON, never a null, and an empty field left out entirely (shared/README.md) -
# that is why sessionLifetime and idleTimeout are missing, and why the db
# object holds nothing but the driver, the file and its key.
#
# config.DB.Validate decides that last part, not taste: with the driver sqlite
# the path has to start with a /, the key has to be 64 bytes, and nodes, name,
# user, password and ca have to be EMPTY. A name or an account next to the path
# would make a configuration the API refuses at its first start.
render_api_json() {
	local noise="$1" sign="$2" secret="$3" challenge="$4" release="$5" dbkey="$6"
	printf '{\n'
	printf '  "node": %s,\n' "$(json_text "$NGC_NAME")"
	printf '  "url": %s,\n' "$(json_text "$TUNNEL_URL")"
	printf '  "listen": %s,\n' "$(json_text ":${API_PORT}")"
	printf '  "cert": %s,\n' "$(json_text "$NGC_CERT")"
	printf '  "certKey": %s,\n' "$(json_text "$NGC_KEY")"
	printf '  "db": {\n'
	printf '    "driver": "sqlite",\n'
	printf '    "path": %s,\n' "$(json_text "$NGC_API_DB")"
	printf '    "key": "%s"\n' "$dbkey"
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
# cannot report a refused character by failing - this asks every value once
# more before a file is written. The keys are not asked: they come out of
# valid_b64url_n or out of openssl.
api_json_ok() {
	local v
	for v in "$NGC_NAME" "$TUNNEL_URL" ":${API_PORT}" "$NGC_CERT" "$NGC_KEY" \
		"$NGC_API_DB" "$STORE_URL"; do
		json_text "$v" >/dev/null || return 1
	done
	return 0
}

# write_api_json makes the keys this machine needs, keeps the ones it has
# already, and writes api.json as root with mode 0600 (shared/ulh.md:
# configuration files with keys).
write_api_json() {
	local noise sign secret challenge release dbkey
	check_two_files
	noise="$(kept_key "$NGC_API_JSON" noiseKey 43)" || noise="$(random_key 32)"
	sign="$(kept_key "$NGC_API_JSON" signKey 43)" || sign="$(random_key 32)"
	secret="$(kept_key "$NGC_API_JSON" secretKey 43)" || secret="$(random_key 32)"
	challenge="$(kept_key "$NGC_API_JSON" challengeKey 43)" || challenge="$(random_key 32)"
	# 64 bytes, not 32: the file is encrypted with AES-256-XTS, which takes two
	# AES-256 keys (config.DB.Key, state.KeySize).
	dbkey="$(kept_db_key)" || dbkey="$(random_key 64)"
	release="$(release_key_b64)" ||
		log_error "The release key in this script is no Ed25519 key in PEM form, so api.json cannot be written. Please get a newer version of ulh."

	ensure_dir "$NGC_ETC" 0755
	ensure_dir "$NGC_TLS" 0755
	# 0700: the file in here IS the database, and it is encrypted with a key
	# that lies in a file of root's. Nobody else has business in the folder.
	ensure_dir "$NGC_API_DB_DIR" 0700
	api_json_ok || log_error "One of the answers carries a character that may not stand in api.json. Nothing was written."
	umask 077
	render_api_json "$noise" "$sign" "$secret" "$challenge" "$release" "$dbkey" >"${WORK}/api.json" ||
		log_error "api.json could not be made."
	chmod 0600 -- "${WORK}/api.json"
	put_file "${WORK}/api.json" "$NGC_API_JSON" 0600 api
}

# ============================================================
# controller.json
# ============================================================

# UNPAIRED_URL, UNPAIRED_KEY and UNPAIRED_HASH are what the provisional
# controller.json carries where the pairing will put the API and the anchor.
#
# Why there is a provisional file at all: ngc-controller pair reads its
# configuration BEFORE it asks for the code (node.pair calls
# config.LoadController first), and config.Validate wants at least one API with
# a key and a TLS fingerprint and an anchor with a sequence number that is not
# zero. The pairing is what brings exactly those values, so the file it reads
# cannot already hold them.
#
# What these three are chosen for is that they can never become trust: the
# address is in the reserved domain .invalid, which resolves nowhere, and the
# key, the fingerprint and the hash of the anchor are 32 zero bytes, which no
# node and no version of a trust list has. And the file never reaches /etc/ngc:
# it lies in WORK, which is 0700, root's and removed when the script ends, and
# only the file the pairing wrote is put in place.
#
# That the local API answers at wss://<hostname>:7443/tunnel makes no
# difference here: the provisional file must NOT name it. The pairing code is
# what says which API to trust and with which key, and a file that named the
# local API with 32 zero bytes for its key would be a file that says "trust
# this" about something it cannot check.
UNPAIRED_URL="wss://unpaired.invalid:7443/tunnel"
UNPAIRED_KEY="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
UNPAIRED_HASH="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

# render_controller_json writes controller.json (config.Controller) for this
# one machine: strict JSON, never a null, and an empty field left out entirely
# (shared/README.md) - that is why podman is missing: config.parseController
# fills in /usr/bin/podman, and the path repeated here would be a second place
# to keep right. node is left out as well: only an admin's trust list gives
# this machine its node ID, and the pairing clears it.
#
# Three things are this machine's own, and all three come from the contract:
#
#   - roles is all four of them (shared/ulh.md, "ngc-all": alle vier Rollen).
#   - webConfig is there BECAUSE the role web is: config.Validate refuses one
#     without the other, both ways round. The file it names is ngc-web's, and
#     the controller keeps it up to date once it is paired.
#   - migrate is there because the role db is, and on this machine it is the
#     API's SQLite file and the API's key, not an account on a database server
#     (shared/ulh.md: "auf dem Pi: SQLite-Datei und Schluessel"). That is the
#     one place where two programs really meet on one file, and the head of
#     this script says what is done about it and what is not measured.
render_controller_json() {
	local noise="$1" dbkey="$2" release="$3" migratekey="$4"
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
	printf '],\n'
	printf '  "webConfig": %s,\n' "$(json_text "$NGC_WEB_JSON")"
	printf '  "migrate": {\n'
	printf '    "driver": "sqlite",\n'
	printf '    "path": %s,\n' "$(json_text "$NGC_API_DB")"
	printf '    "key": "%s"\n' "$migratekey"
	printf '  }\n'
	printf '}\n'
}

# controller_json_ok says whether every text of the configuration survived
# json_text, for the same reason api_json_ok does.
controller_json_ok() {
	local v
	for v in "$NGC_NAME" "$UNPAIRED_URL" "$NGC_STATE" "$NGC_API_DB" "$NGC_WEB_JSON" \
		"${ROLES[@]}"; do
		json_text "$v" >/dev/null || return 1
	done
	return 0
}

# write_provisional makes the configuration the pairing reads: a key of this
# machine, the key of the controller's own file, and the access for the
# migrations. The key of the controller's store is kept where there is one -
# see kept_key - and the key of the migrations is no key of its own at all: it
# is the API's, read out of api.json, because it is the API's file that gets
# migrated.
write_provisional() {
	local noise dbkey release migratekey
	check_two_files
	noise="$(random_key 32)"
	dbkey="$(kept_key "$NGC_CONF" dbKey 86)" || dbkey="$(random_key 64)"
	migratekey="$(kept_db_key)" ||
		log_error "The key of the database could not be read out of ${NGC_API_JSON}. Without it the controller cannot play the migrations of an update. Call 'Set up this machine' first."
	release="$(release_key_b64)" ||
		log_error "The release key in this script is no Ed25519 key in PEM form, so controller.json cannot be written. Please get a newer version of ulh."
	controller_json_ok || log_error "One of the answers carries a character that may not stand in controller.json. Nothing was written."
	umask 077
	render_controller_json "$noise" "$dbkey" "$release" "$migratekey" >"${WORK}/controller.json" ||
		log_error "controller.json could not be made."
	chmod 0600 -- "${WORK}/controller.json"
}

# ============================================================
# PAIRING
# ============================================================

# pair_controller runs "ngc-controller pair" with the code out of the browser.
# The code goes in through the standard input and never into the command line:
# /proc/<pid>/cmdline is readable by every local user without hidepid
# (shared/ulh.md). The configuration ngc-controller writes is the provisional
# one in WORK with the API and the anchor of the pairing in it; only that file
# is put into /etc/ngc.
#
# The output is not caught and not filtered: the two lines ngc-controller
# prints are the fingerprint of this machine's key and the anchor out of the
# code, and the admin has to see them to compare them with the browser. Neither
# of the two is the code.
pair_controller() {
	log_section "Pairing the controller of this machine"
	log_warn "Compare the fingerprint and the anchor below with what the web interface shows. If they differ, break this off: something else is answering there."
	ensure_dir "$NGC_ETC" 0755
	if ! printf '%s\n' "$NGC_PAIR_CODE" |
		"${NGC_BIN}/ngc-controller" -config "${WORK}/controller.json" pair; then
		log_error "The pairing did not work (the message of ngc-controller is above). Nothing was written: ${NGC_CONF} is untouched. A pairing code is good once and for a short time, so get a new one in the web interface and run this again."
	fi
	if [ ! -s "${WORK}/controller.json" ] || [ ! -s "$NGC_ANCHOR" ]; then
		log_error "ngc-controller came back without writing its configuration or the anchor ${NGC_ANCHOR}. Nothing was changed; get a new pairing code and run this again."
	fi
	# The pairing replaced the provisional address of the API, and that is what
	# says it really happened: a file still naming unpaired.invalid would be
	# one the pairing never wrote.
	if grep -q 'unpaired\.invalid' "${WORK}/controller.json"; then
		log_error "The configuration ngc-controller wrote still names no API, so the pairing did not come off. Nothing was changed; get a new pairing code and run this again."
	fi
	put_file "${WORK}/controller.json" "$NGC_CONF" 0600 ctrl
	chmod 0600 -- "$NGC_ANCHOR"
	chown root:root -- "$NGC_ANCHOR"
	ensure_dir "$NGC_STATE_DIR" 0700
	: >"${WORK}/paired"
	put_file "${WORK}/paired" "$NGC_PAIRED" 0600 ctrl
	log_info "The controller of this machine is paired."
}

# paired says whether a pairing came off on this machine already, so a second
# run does not pair again with a code that is long spent.
paired() {
	[ -f "$NGC_PAIRED" ] && [ -f "$NGC_CONF" ]
}

# change_settings writes the roles, webConfig and migrate into the
# controller.json that is there, and leaves everything the pairing owns alone:
# name, noiseKey, node, apis and anchor. jq does it, because those five cannot
# be made again out of the answers - a fresh key would put this machine out of
# its own trust list, and a fresh dbKey would leave the controller's store
# unreadable.
#
# jq is asked for a whole file and the file is replaced atomically with mode
# 0600, so no reader ever sees half of it and the keys are never for one moment
# readable by anybody else.
change_settings() {
	local migratekey
	check_two_files
	migratekey="$(kept_db_key)" ||
		log_error "The key of the database could not be read out of ${NGC_API_JSON}. Nothing was changed."
	jq --argjson roles "$(roles_json)" \
		--arg web "$NGC_WEB_JSON" \
		--arg path "$NGC_API_DB" \
		--arg key "$migratekey" \
		'.roles = $roles
		 | .webConfig = $web
		 | .migrate = {driver: "sqlite", path: $path, key: $key}' \
		<"$NGC_CONF" >"${WORK}/changed.json" ||
		log_error "The settings in ${NGC_CONF} could not be changed. Is the file still the one NGC wrote?"
	if [ ! -s "${WORK}/changed.json" ]; then
		log_error "The new ${NGC_CONF} came out empty. Nothing was changed."
	fi
	chmod 0600 -- "${WORK}/changed.json"
	put_file "${WORK}/changed.json" "$NGC_CONF" 0600 ctrl
}

# roles_json prints the four roles as a JSON list. jq builds it, so nothing of
# an answer is pasted into the program of jq itself; the roles are a constant
# of this script anyway.
roles_json() {
	printf '%s\n' "${ROLES[@]}" | jq -R . | jq -s .
}

# ============================================================
# THE SERVICES
# ============================================================

# render_unit_api writes ngc-api.service (config.ServiceAPI). The API runs as
# root: it binds port 7443 and reads api.json, which is 0600 and root's. What
# it does not need is taken away instead - no new privileges, a read-only
# system, and only the places it writes.
#
# ReadWritePaths carries /var/lib/ngc because on this machine the DATABASE
# lives in there as a file, not on a database server. The line looks the same
# as its sibling's, and the comment is here so that nobody narrows it later
# without knowing that the whole installation hangs on it.
render_unit_api() {
	printf '%s\n' \
		'# /etc/systemd/system/ngc-api.service' \
		'# Written by ngc-all.sh of ulh (install, configure). Never edit by hand.' \
		'[Unit]' \
		'Description=NextGenCloud API' \
		'Documentation=https://github.com/sorglos-it/nextgencloud' \
		'After=network-online.target' \
		'Wants=network-online.target' \
		'' \
		'[Service]' \
		'Type=simple' \
		"ExecStart=${NGC_BIN}/ngc-api -config ${NGC_API_JSON}" \
		'# On SQLite the API migrates its own file at every start. Whoever does' \
		'# not get the migration lock does not start, on purpose - so the' \
		'# restart belongs here, and a few seconds is the right distance: the' \
		'# lock falls when the other run is finished.' \
		'Restart=on-failure' \
		'RestartSec=5' \
		'# /run/ngc, where the API keeps what one run needs.' \
		'RuntimeDirectory=ngc' \
		'RuntimeDirectoryMode=0700' \
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

# render_unit_ctrl writes ngc-controller.service (config.ServiceController).
#
# Two lines in here are decisions, and both belong to this script rather than
# to its sibling:
#
# 1. "After=network-online.target ngc-api.service". On this one machine both
#    programs start at every boot, and with the role db the controller carries
#    the access to the API's own file for the migrations of an update. The
#    order is what makes exactly ONE of them migrate first instead of two
#    meeting in the same file: the API, which owns it. systemd orders the two
#    because both units are enabled and so both are in the same transaction;
#    there is deliberately no Wants and no Requires on ngc-api.service, because
#    a controller that stops whenever the API is down would be worse than one
#    that keeps its tunnels and retries.
# 2. "Restart=on-failure" with "RestartSec=5" (NGC docs/vertraege-v1.2.md,
#    point 32, decided 12.10.2026): a controller that cannot get the migration
#    lock of its own store does NOT start, on purpose - state.Open does not
#    wait, because a service that "runs" and does nothing for up to 900 seconds
#    is worse for an admin than one that fails with a line naming the reason.
#    The common case is an overlapping restart, and the lock falls as soon as
#    the other run is finished, not after its 900 seconds - so the distance is
#    a few seconds and NOT anywhere near the lock time. Five seconds also keeps
#    the unit out of systemd's own start limit (5 starts in 10 seconds by
#    default): five restarts at this distance take 25 seconds.
#
# What this unit does NOT do is take rights away the way ngc-api.service does.
# The controller makes system accounts, mounts encrypted data folders and
# starts containers through podman; ProtectSystem=strict, NoNewPrivileges or
# RestrictNamespaces would each stop one of those, and a sandbox with holes in
# it for all three would say "sandbox" and mean nothing. It runs as root, and
# that is written here so that nobody has to work it out from the file.
render_unit_ctrl() {
	printf '%s\n' \
		'# /etc/systemd/system/ngc-controller.service' \
		'# Written by ngc-all.sh of ulh (install, configure). Never edit by hand.' \
		'[Unit]' \
		'Description=NextGenCloud Controller' \
		'Documentation=https://github.com/sorglos-it/nextgencloud' \
		'# Everything runs on this one machine, and with the role db this' \
		'# controller carries the access to the file of the API for the' \
		'# migrations of an update. The API starts first, so exactly one of the' \
		'# two migrates that file.' \
		'After=network-online.target ngc-api.service' \
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
		'' \
		'[Install]' \
		'WantedBy=multi-user.target'
}

# service_apply starts a service, and restarts it only when something of ITS
# own changed: a running API drops every open session when it goes, and a
# running controller holds the tunnels and the channels of every app, so
# neither is restarted for nothing (shared/ulh.md: a second run changes nothing
# that is right).
service_apply() {
	local unit="$1" changed="$2" what="$3"
	systemctl daemon-reload || log_error "systemd did not take the new service files."
	if ! systemctl is-active --quiet "$unit"; then
		systemctl enable --now "$unit" ||
			log_error "The service ${unit} could not be started. 'journalctl -u ${unit}' says why."
		log_info "The ${what} is running, and from now on it starts with the machine."
		return 0
	fi
	if [ "$changed" -eq 0 ]; then
		log_info "Nothing changed, the ${what} keeps running as it is."
		return 0
	fi
	systemctl restart "$unit" ||
		log_error "The service ${unit} could not be restarted. 'journalctl -u ${unit}' says why."
	log_info "The ${what} has taken the new settings."
}

# wait_for_cert waits for the certificate ngc-api makes for itself at its first
# start. Without it there is no fingerprint to show, and without that no web
# server can be set up - so this waits instead of leaving the admin without the
# one thing the end of this script is here to print.
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

install_ngc_all() {
	need_root
	need_debian
	work_init
	check_two_files
	log_section "Setting up NextGenCloud on ${NGC_HOSTNAME}"
	read_answers
	ensure_packages
	install_release
	write_api_json
	render_unit_api >"${WORK}/ngc-api.service"
	put_file "${WORK}/ngc-api.service" "$UNIT_API" 0644 api
	service_apply "$NAME_API" "$CHANGED_API" "API"
	# The controller comes after the first setup, with a pairing code out of
	# the browser (shared/ulh.md, "ngc-all"). A machine that is paired already
	# keeps its pairing and only gets its settings written again.
	if paired; then
		change_settings
		render_unit_ctrl >"${WORK}/ngc-controller.service"
		put_file "${WORK}/ngc-controller.service" "$UNIT_CTRL" 0644 ctrl
		service_apply "$NAME_CTRL" "$CHANGED_CTRL" "controller"
	fi
	show_next_steps
}

configure_ngc_all() {
	need_root
	need_debian
	work_init
	check_two_files
	log_section "Changing the settings of NextGenCloud on this machine"
	read_answers
	if ! programs_here; then
		log_error "The programs of NGC are not in ${NGC_BIN} yet. Call 'Set up this machine' first."
	fi
	write_api_json
	render_unit_api >"${WORK}/ngc-api.service"
	put_file "${WORK}/ngc-api.service" "$UNIT_API" 0644 api
	service_apply "$NAME_API" "$CHANGED_API" "API"

	if [ -n "$NGC_PAIR_CODE" ]; then
		# A new code means a new pairing: ngc-controller makes a new key, so
		# this machine leaves its own trust list and an admin has to enter it
		# again. The key of the controller's store is kept (kept_key), so
		# nothing it noted down is lost over it.
		write_provisional
		pair_controller
	elif paired; then
		change_settings
	else
		log_error "The controller of this machine is not paired yet. Sign in to the web interface with the setup code, make a pairing code there and give it as the answer pair_code."
	fi
	render_unit_ctrl >"${WORK}/ngc-controller.service"
	put_file "${WORK}/ngc-controller.service" "$UNIT_CTRL" 0644 ctrl
	service_apply "$NAME_CTRL" "$CHANGED_CTRL" "controller"
	show_next_steps
}

uninstall_ngc_all() {
	local f
	need_root
	need_debian
	work_init
	log_section "Removing NextGenCloud from this machine"

	for f in "$NAME_CTRL" "$NAME_API"; do
		systemctl disable --now "$f" >/dev/null 2>&1 || true
	done
	rm -f -- "$UNIT_CTRL" "$UNIT_API"
	systemctl daemon-reload || true
	rm -f -- "${NGC_BIN}/ngc-api" "${NGC_BIN}/ngc-store" "${NGC_BIN}/ngc-controller"
	log_info "The two services and the programs in ${NGC_BIN} are gone."

	if [ "$NGC_PURGE" = yes ]; then
		# The warning comes BEFORE the deletion. After it, it is a log entry
		# and no warning - and on ONE machine it is the whole installation that
		# goes: the key in api.json is what the database file is encrypted
		# with, the key in controller.json what the data of every app is
		# encrypted with, and neither has a second copy anywhere.
		log_warn "Now removing ${NGC_API_JSON}, ${NGC_CONF}, the anchor, the database of this machine and the data of the apps. The keys in those two files are what all of it is encrypted with, and there is no second copy of them. Once they are gone, nothing opens any of it again. Put the two files away first if you are not sure."
		for f in "$NGC_API_JSON" "$NGC_CONF" "$NGC_ANCHOR" "$NGC_CERT" "$NGC_KEY" "$NGC_SETUP_CODE"; do
			rm -f -- "$f"
		done
		rm -rf -- "${NGC_API_DB_DIR:?}" "${NGC_STATE_DIR:?}" "${NGC_KEPT:?}" "${NGC_DATA:?}/apps"
		log_warn "Deleted: api.json, controller.json, the anchor, the database and the data of the apps."
	else
		# Kept data stays under /var/lib/ngc/, so a new installation finds it
		# again (shared/ulh.md). 0700 and root's: both files hold keys.
		ensure_dir "$NGC_KEPT" 0700
		for f in "$NGC_API_JSON" "$NGC_CONF" "$NGC_ANCHOR" "$NGC_CERT" "$NGC_KEY"; do
			if [ -f "$f" ]; then
				cp -p -- "$f" "${NGC_KEPT}/"
			fi
		done
		log_info "Kept: api.json, controller.json, the anchor and the certificate stay in ${NGC_ETC}, with a copy of them under ${NGC_KEPT}; the database and the data of the apps stay under ${NGC_DATA}."
	fi
	log_info "Done."
}

# show_next_steps prints what the rest of the installation waits for: the
# fingerprint of the TLS key of this machine, which ngc-web needs
# (shared/ulh.md, "TLS intern, nie ungeprueft"), the setup code of the first
# admin account as long as there is one, and the pairing of the controller.
#
# The fingerprint of the controller's key is NOT printed here: ngc-controller
# printed it during the pairing, and a second copy out of a file would be one
# this script computed instead of the program that holds the key.
show_next_steps() {
	local pin
	printf '\n'
	if ! wait_for_cert; then
		log_warn "The API has not made its certificate (${NGC_CERT}) yet, so there is no fingerprint to show. Look at 'journalctl -u ${NAME_API}', and when the API is running call 'Change the settings' once more - it prints the fingerprint."
		return 0
	fi
	# The exit status of pin_of_cert decides, as shared/ulh.md asks of pin.sh:
	# a fingerprint that could not be computed is no fingerprint, and a wrong
	# one would be written into the configuration of the web server.
	pin="$(pin_of_cert "$NGC_CERT")" ||
		log_error "The certificate ${NGC_CERT} could not be read, so its fingerprint cannot be shown. Without it no web server may be set up: it is what the web server checks this API by."
	log_info "Done. What comes next:"
	printf '\n'
	printf '  The fingerprint of the API on this machine:\n'
	printf '    %s\n' "$pin"
	printf '  Set up the web interface with ngc-web, and give it this machine\n'
	printf '  (https://%s:%s) and the fingerprint above.\n' "$NGC_HOSTNAME" "$API_PORT"
	if [ -s "$NGC_SETUP_CODE" ]; then
		printf '\n'
		printf '  The setup code for the first admin account:\n'
		printf '    %s\n' "$(cat -- "$NGC_SETUP_CODE")"
		printf '  Open the web interface in a browser and type it in there. It\n'
		printf '  works once, and the API deletes it afterwards. You name the\n'
		printf '  first administrator there, not here.\n'
		printf '\n'
		log_warn "Whoever has that code makes the first admin account of this installation. Nobody needs it but you, and it is in no log."
	fi
	if ! paired; then
		printf '\n'
		printf '  The controller is not paired yet, so no app can run. Sign in to\n'
		printf '  the web interface, make a pairing code for this machine there,\n'
		printf '  and call "Pair the controller" with it.\n'
	else
		printf '\n'
		printf '  How it is doing: systemctl status %s %s\n' "$NAME_API" "$NAME_CTRL"
	fi
}

# ============================================================
# MAIN
# ============================================================

case "$ACTION" in
install)
	install_ngc_all
	;;
configure | config)
	configure_ngc_all
	;;
uninstall)
	uninstall_ngc_all
	;;
*)
	# Prints the actions and their parameters from the catalog.
	print_usage ngc-all && exit 1
	;;
esac

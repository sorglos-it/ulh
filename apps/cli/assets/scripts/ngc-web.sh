#!/bin/bash

# ngc-web - NextGenCloud: the web interface on Apache (Debian and Ubuntu).
#
# What it does: Apache and PHP from the package sources, the web interface in
# /var/www/ngc/ with only its public/ as the web root, the certificate for the
# browser, the certificate of every API checked against its pin, /etc/ngc/web.json
# and Apache's balancer for /api/. Contract: shared/ulh.md of the NGC repository
# (github.com/sorglos-it/nextgencloud), rules "TLS intern, nie ungeprueft",
# "Hosts und Adressen" and "Lastverteilung in Apache".
#
# The prompts of assets/catalog.yaml carry the answers of that contract, in
# this order (ulh joins them with commas, so no answer may hold a comma -
# that is why the two lists are separated by spaces):
#   1 hostname   NGC_HOSTNAME   name or IPv4 address the browser calls
#   2 cert_mode  NGC_CERT_MODE  letsencrypt, selfsigned or import
#   3 cert_file  NGC_CERT_FILE  import: the certificate in PEM
#   4 key_file   NGC_KEY_FILE   import: its private key in PEM
#   5 apis       NGC_APIS       https://<host>:7443 of every API server
#   6 api_pins   NGC_API_PINS   the pin of each API, in the same order
#
# Everything this script prints is English, as in every other ulh script. The
# five languages of ulh sit in assets/catalog.yaml: the menu entry, the actions
# and all six questions are there in de, en, fr, it and es.
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
# slipped through would end up in Apache's configuration (shared/ulh.md,
# "Hosts und Adressen").
LC_ALL=C
export LC_ALL

# ============================================================
# WHERE EVERYTHING LIVES (package config of the NGC contract)
# ============================================================

NGC_ETC="/etc/ngc"                              # config.Dir
NGC_TLS="/etc/ngc/tls"
NGC_WEB_JSON="/etc/ngc/web.json"                # config.WebFile
NGC_BALANCER="/etc/ngc/apache-apis.conf"        # config.BalancerFile
NGC_TRUST="/etc/ngc/tls/api-trust.pem"          # config.APITrustFile
NGC_CERT="/etc/ngc/tls/web.crt"                 # the certificate for the browser
NGC_KEY="/etc/ngc/tls/web.key"
NGC_ROOT="/var/www/ngc"                         # config.WebRoot, web root is its public/
NGC_DATA="/var/lib/ngc"                         # config.DataDir
NGC_SEQ="/var/lib/ngc/release.seq"              # the release installed last
NGC_STAGE="/var/lib/ngc/staged"                 # config.StageDir: release files put here by hand
NGC_KEPT="/var/lib/ngc/web"                     # uninstall keeps the configuration here
SITE_FILE="/etc/apache2/sites-available/ngc-web.conf"
MD_FILE="/etc/apache2/conf-available/ngc-md.conf"

# Packages: Apache and PHP for the interface, openssl and jq for the check of
# the program files, curl to fetch the release, ca-certificates so that check
# can reach the release server at all.
NGC_PACKAGES=(apache2 php-fpm openssl jq curl ca-certificates)

# Apache modules the virtual host and the balancer need. mod_md (Let's
# Encrypt) comes on top, only in that mode.
NGC_MODULES=(ssl rewrite headers proxy proxy_http proxy_wstunnel proxy_balancer
	lbmethod_byrequests proxy_fcgi setenvif)

# Where the release files come from. The address carries no trust at all: the
# signature of release.json and the SHA-256 of the file do (verify_release), so
# a mirror, NGC_RELEASE_BASE or a copy in /var/lib/ngc/staged is exactly as
# safe as this one.
NGC_RELEASE_BASE="${NGC_RELEASE_BASE:-https://github.com/sorglos-it/nextgencloud/releases/latest/download}"

# The public key of NGC's releases (sign.PurposeRelease), fixed in the script.
# It is the whole trust in a release. The placeholder below is not a key, so
# every install stops at the check - which is the safe way round until the real
# key is in here.
NGC_RELEASE_KEY="-----BEGIN PUBLIC KEY-----
REPLACE-THIS-LINE-WITH-THE-NGC-RELEASE-KEY
-----END PUBLIC KEY-----"

# The answers. parse_parameters exported them, so they are read from the
# environment; an answer nobody gave is the empty text and not an error of
# set -u. Every one of them is checked in read_answers before it is used.
NGC_HOSTNAME="${NGC_HOSTNAME:-}"
NGC_CERT_MODE="${NGC_CERT_MODE:-}"
NGC_CERT_FILE="${NGC_CERT_FILE:-}"
NGC_KEY_FILE="${NGC_KEY_FILE:-}"
NGC_APIS="${NGC_APIS:-}"
NGC_API_PINS="${NGC_API_PINS:-}"
NGC_PURGE="${NGC_PURGE:-no}"

APIS=()         # the checked addresses of the APIs, in the order given
PINS=()         # their pins, same order
RP_ID=""        # the name for passkeys, empty for an IP address
PHP_CONF=""     # Debian's php<version>-fpm configuration of Apache
RELEASE_NAME="" # the file of ngc-web in the release
CHANGED=0       # something was written: Apache needs to be reloaded
WORK=""         # temporary directory, removed on exit

# ============================================================
# SMALL HELPERS
# ============================================================

# work_init makes the temporary directory and has it removed again, whatever
# ends the script: nothing of a release stays behind half checked.
work_init() {
	if [ -n "$WORK" ]; then
		return 0
	fi
	WORK="$(mktemp -d)"
	trap 'rm -rf -- "$WORK"' EXIT
	trap 'exit 1' HUP INT TERM
}

# need_root stops before anything is touched: the script writes in /etc, /var
# and Apache's configuration.
need_root() {
	if [ "$EUID" -ne 0 ]; then
		log_error "This script needs root rights. Start it from ulh, or with: sudo bash $0 \"<action>\""
	fi
}

# need_debian keeps the script to what it was written for: the package names,
# a2enmod and /etc/apache2 are Debian's and Ubuntu's.
need_debian() {
	detect_os
	if [ "$PKG_TYPE" != "deb" ]; then
		log_error "NGC sets up its web interface on Debian and Ubuntu only. Found: ${OS_DISTRO}."
	fi
}

# is_ipv4 tells a dotted address from a name: its last label is all digits.
# valid_host has already made sure it is one of the two.
is_ipv4() {
	case "${1##*.}" in
	'' | *[!0-9]*) return 1 ;;
	esac
	return 0
}

# ============================================================
# THE GRAMMAR OF HOSTS, ADDRESSES AND PINS
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

# valid_web_url: exactly "https://" host ":" port and at most 256 bytes
# (trust.ValidWebURL over trust.ValidHostPort). Only such an address may reach
# web.json and Apache.
valid_web_url() {
	local u="${1:-}" hp
	if [ "${#u}" -gt 256 ]; then
		return 1
	fi
	case "$u" in
	https://*) hp="${u#https://}" ;;
	*) return 1 ;;
	esac
	# The port is split at the last colon, as ValidHostPort does; IPv6 in
	# brackets never gets here because valid_host refuses the brackets.
	case "$hp" in
	*:*) ;;
	*) return 1 ;;
	esac
	valid_host "${hp%:*}" && valid_port "${hp##*:}"
}

# valid_pin: a pin as shared/testdata/tls/pin.sh prints it - base64url of a
# SHA-256 without padding, so 43 of exactly these characters (trust.TLSPin).
# Whether it is the right key is decided later, by comparing it with the pin of
# the certificate the API itself answered with.
valid_pin() {
	local p="${1:-}"
	if [ "${#p}" -ne 43 ]; then
		return 1
	fi
	case "$p" in
	*[!A-Za-z0-9_-]*) return 1 ;;
	esac
	return 0
}

# pin_of_cert prints the pin of a certificate's key, exactly as
# shared/testdata/tls/pin.sh does: base64url without padding of the SHA-256 of
# the SubjectPublicKeyInfo.
pin_of_cert() {
	local key pin
	# A pipeline fails only with its last command, so the key is read on its
	# own: a certificate that cannot be read must not turn into a pin.
	key="$(openssl x509 -in "$1" -noout -pubkey 2>/dev/null)" || return 1
	pin="$(printf '%s\n' "$key" | openssl pkey -pubin -outform DER 2>/dev/null |
		openssl dgst -sha256 -binary | base64 -w0 | tr '+/' '-_' | tr -d '=')"
	# A step above that failed left nothing to hash; the SHA-256 of nothing is
	# no key's pin.
	if [ "${#pin}" -ne 43 ] || [ "$pin" = "47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU" ]; then
		return 1
	fi
	printf '%s\n' "$pin"
}

# ============================================================
# READING THE ANSWERS
# ============================================================

# read_answers checks every answer before anything is installed or written.
# Nothing unchecked may reach a configuration file of another program.
read_answers() {
	local i j url pin
	local -a urls=() pins=()

	if ! valid_host "$NGC_HOSTNAME"; then
		log_error "This name of the web server is not allowed: '${NGC_HOSTNAME}'. Take a name in lower case (for example ngc.example.org) or an IPv4 address (for example 192.168.1.10). No IPv6, and nothing with http:// in front."
	fi

	case "$NGC_CERT_MODE" in
	letsencrypt | selfsigned | import) ;;
	*)
		log_error "There are three ways to a certificate: letsencrypt, selfsigned or import. This is none of them: '${NGC_CERT_MODE}'."
		;;
	esac
	if [ "$NGC_CERT_MODE" = letsencrypt ] && is_ipv4 "$NGC_HOSTNAME"; then
		log_error "Let's Encrypt works for a name only, not for an IP address. Take selfsigned, or set up a name that points at this server from the internet."
	fi
	if [ "$NGC_CERT_MODE" = import ]; then
		check_import_file "$NGC_CERT_FILE" "certificate"
		check_import_file "$NGC_KEY_FILE" "key"
	fi

	# Passkeys only work with a name, so rp stays out of web.json for an IP
	# address (shared/ulh.md: rp.id and rp.origins both or neither).
	if is_ipv4 "$NGC_HOSTNAME"; then
		RP_ID=""
	else
		RP_ID="$NGC_HOSTNAME"
	fi

	# read -a splits at spaces: the lists cannot hold commas, ulh's parameter
	# format uses those (parse_parameters).
	read -r -a urls <<<"$NGC_APIS"
	read -r -a pins <<<"$NGC_API_PINS"
	if [ "${#urls[@]}" -eq 0 ]; then
		log_error "The address of the API server is missing, for example https://api-1.example.org:7443. Separate several of them with a space."
	fi
	if [ "${#urls[@]}" -gt 16 ]; then
		log_error "At most 16 API servers, and there are ${#urls[@]}."
	fi
	if [ "${#urls[@]}" -ne "${#pins[@]}" ]; then
		log_error "Every API address needs exactly one fingerprint, in the same order. Addresses: ${#urls[@]}, fingerprints: ${#pins[@]}."
	fi

	for i in "${!urls[@]}"; do
		url="${urls[$i]}"
		pin="${pins[$i]}"
		if ! valid_web_url "$url"; then
			log_error "This address of an API is not allowed: '${url}'. Expected is https://<name or IPv4>:<port>, for example https://api-1.example.org:7443."
		fi
		if ! valid_pin "$pin"; then
			log_error "The fingerprint of the API ${url} is not allowed: '${pin}'. Expected are the 43 characters ngc-api shows at the end, exactly as they are there."
		fi
		# The same address twice would let Apache balance over it twice and
		# trust two keys for one server (config.Web.Validate).
		j=0
		while [ "$j" -lt "${#APIS[@]}" ]; do
			if [ "${APIS[$j]}" = "$url" ]; then
				log_error "The address ${url} is in the list twice."
			fi
			j=$((j + 1))
		done
		APIS+=("$url")
		PINS+=("$pin")
	done
}

# check_import_file refuses a path that is not an absolute, readable file, so
# the admin learns of a typo here and not from Apache's log.
check_import_file() {
	local f="${1:-}" what="$2"
	case "$f" in
	/*) ;;
	*) log_error "The way 'import' needs the full path to the ${what}, so with a / at the start. This is not one: '${f}'." ;;
	esac
	if [ ! -f "$f" ] || [ ! -r "$f" ]; then
		log_error "There is no such file, or it cannot be read: ${f}"
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
# of install changes nothing that is already right, and Apache is reloaded only
# when something really changed (shared/ulh.md). The new file is written next to
# the old one and renamed, so a reader never sees half a file.
put_file() {
	local src="$1" dst="$2" mode="$3" tmp
	if [ -f "$dst" ] && cmp -s -- "$src" "$dst"; then
		chown root:root -- "$dst"
		chmod "$mode" -- "$dst"
		log_info "unchanged: ${dst}"
		return 0
	fi
	tmp="$(mktemp -- "${dst}.XXXXXX")"
	# All four steps or none: a full disk must not leave half a file lying
	# next to the real one, where the next run would find it again.
	if ! {
		cat -- "$src" >"$tmp" &&
			chown root:root -- "$tmp" &&
			chmod "$mode" -- "$tmp" &&
			mv -f -- "$tmp" "$dst"
	}; then
		rm -f -- "$tmp"
		log_error "The file ${dst} could not be written. Is the disk full?"
	fi
	CHANGED=1
	log_info "written: ${dst}"
}

# ============================================================
# THE RELEASE: FETCH, CHECK, UNPACK
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

# release_payload decodes the payload of release.json into $WORK/payload.json.
# Nothing in it is trusted before verify_release has run; it is read this early
# only to learn the name of the file to fetch.
release_payload() {
	jq -er '.payload | strings' <"$1/release.json" >"$WORK/payload.txt" ||
		return 1
	b64url <"$WORK/payload.txt" >"$WORK/payload.json" || return 1
}

# release_file prints the file name of part ngc-web, arch all: the last segment
# of the entry's url, and only if it is a name and not a path (same rule as
# verify.sh, which checks it again).
release_file() {
	local url name
	url="$(jq -er '[.files[]? | select(.part == "ngc-web" and .arch == "all")]
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
# entry for ngc-web/all with its file name, SHA-256 and size. It writes nothing
# into the directory and says "release wrong: <reason>" when something is off.
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
		jq -r '
			if (.files | type) != "array" then error("files is not a list") else . end
			| [.files[] | select(.part == "ngc-web" and .arch == "all")]
			| if length != 1 then error("not exactly one entry") else .[0] end
			| if (.url | type) == "string" and (.sha256 | type) == "string" and (.size | type) == "number"
			then [.url, .sha256, (.size | tostring)] | @tsv else error("entry of wrong types") end
		' "$WORK/v.payload.json" >"$WORK/v.entry.tsv" || fail "no single valid entry for ngc-web all"
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

# fetch_release puts release.json and the one file of ngc-web into a directory
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
		RELEASE_NAME="$(release_file)" || log_error "There is no entry for ngc-web in ${NGC_STAGE}/release.json."
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
	RELEASE_NAME="$(release_file)" || log_error "There is no entry for ngc-web in release.json. That file does not belong to this script."
	download "${NGC_RELEASE_BASE}/${RELEASE_NAME}" "${dir}/${RELEASE_NAME}"
}

# download fetches one file over HTTPS and nothing else: no other protocol,
# not even after a redirect, and never more than 256 MB.
download() {
	curl --proto '=https' --proto-redir '=https' --tlsv1.2 --location \
		--fail --silent --show-error --max-time 600 --max-filesize 268435456 \
		--output "$2" -- "$1"
}

# install_release checks the release and unpacks the interface into
# /var/www/ngc/, with only its public/ as the web root.
install_release() {
	local dir seq have
	dir="${WORK}/release"
	mkdir -p -- "$dir"

	case "$NGC_RELEASE_KEY" in
	*REPLACE-THIS-LINE*)
		log_error "This script has no real release key of NGC yet. Without it nobody can check whether the program files are genuine, so the setup stops here. Please get a newer version of ulh."
		;;
	esac

	if ! fetch_release "$dir"; then
		if [ -f "${NGC_ROOT}/public/index.php" ] && [ -f "$NGC_SEQ" ]; then
			log_warn "The program files could not be loaded. It stays with the files in ${NGC_ROOT}, which were checked before."
			return 0
		fi
		log_error "The program files could not be loaded. Check the internet connection, or put release.json and the file of ngc-web into ${NGC_STAGE} by hand. As long as NGC has published no release, that folder is the only way that works."
	fi

	if ! verify_release "$dir"; then
		log_error "The program files are not signed by NGC (the reason is above). Nothing is installed. Get ulh again and try once more; if it stays that way, report it at github.com/sorglos-it/ulh/issues."
	fi
	log_info "The signature of the program files is good."

	# Never a release older than the one installed; the same number may come
	# again to repair an installation (shared/ulh.md). The number is read out
	# of the payload verify_release just confirmed, not out of the one that was
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
	if [ "$seq" -eq "$have" ] && [ -f "${NGC_ROOT}/public/index.php" ]; then
		log_info "The web interface is here in this version already (release ${seq})."
		return 0
	fi

	unpack_release "${dir}/${RELEASE_NAME}"
	ensure_dir "$NGC_DATA" 0755
	printf '%s\n' "$seq" >"${WORK}/seq"
	put_file "${WORK}/seq" "$NGC_SEQ" 0644
}

# unpack_release unpacks the checked archive. Safe unpacking of NGC
# (shared/README.md): no absolute path, no "..", no links, no device files.
# The interface is plain files and folders, so anything else means the archive
# is not the one NGC builds.
unpack_release() {
	local tarball="$1" entry
	if ! tar -tf "$tarball" >"${WORK}/entries" 2>/dev/null; then
		log_error "The file that arrived is no archive that can be read."
	fi
	while IFS= read -r entry; do
		case "$entry" in
		/* | .. | ../* | */../* | */.. | '')
			log_error "The archive holds a path that leads out of the target folder. Nothing is unpacked."
			;;
		esac
	done <"${WORK}/entries"
	# Only files and folders: the first letter of tar's long listing is the
	# kind, so l (link), h (hard link), b, c, p and s are refused.
	if tar -tvf "$tarball" 2>/dev/null | grep -qv '^[-d]'; then
		log_error "The archive holds links or device files. Nothing is unpacked."
	fi

	rm -rf -- "${NGC_ROOT}.new"
	mkdir -p -- "${NGC_ROOT}.new"
	tar -xf "$tarball" -C "${NGC_ROOT}.new" --no-same-owner --no-same-permissions ||
		log_error "The archive could not be unpacked."
	if [ ! -f "${NGC_ROOT}.new/public/index.php" ]; then
		rm -rf -- "${NGC_ROOT}.new"
		log_error "public/index.php is missing in the archive. It does not belong to this script."
	fi

	# root owns everything, Apache only reads: the interface needs no write
	# right of its own, its data live in /var/lib/ngc.
	chown -R root:root -- "${NGC_ROOT}.new"
	find "${NGC_ROOT}.new" -type d -exec chmod 0755 -- {} +
	find "${NGC_ROOT}.new" -type f -exec chmod 0644 -- {} +

	rm -rf -- "${NGC_ROOT}.old"
	if [ -d "$NGC_ROOT" ]; then
		mv -- "$NGC_ROOT" "${NGC_ROOT}.old"
	fi
	mv -- "${NGC_ROOT}.new" "$NGC_ROOT"
	rm -rf -- "${NGC_ROOT}.old"
	CHANGED=1
	log_info "The web interface is in ${NGC_ROOT}; only ${NGC_ROOT}/public can be reached from outside."
}

# ============================================================
# APACHE AND PHP
# ============================================================

ensure_packages() {
	local p
	local -a missing=()
	for p in "${NGC_PACKAGES[@]}"; do
		if ! dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q '^install ok installed$'; then
			missing+=("$p")
		fi
	done
	if [ "${#missing[@]}" -eq 0 ]; then
		log_info "Apache, PHP and the tools for the check are installed already."
		return 0
	fi
	log_info "Installing: ${missing[*]}"
	# PKG_UPDATE and PKG_INSTALL are commands with options, so they are meant
	# to split into words here; the package names stay quoted.
	$PKG_UPDATE || true
	$PKG_INSTALL "${missing[@]}" || log_error "These packages could not be installed: ${missing[*]}"
}

ensure_modules() {
	local m
	local -a mods=("${NGC_MODULES[@]}")
	if [ "$NGC_CERT_MODE" = letsencrypt ]; then
		mods+=(md)
	fi
	for m in "${mods[@]}"; do
		if [ ! -e "/etc/apache2/mods-enabled/${m}.load" ]; then
			a2enmod -q "$m" || log_error "The Apache module ${m} could not be switched on."
			CHANGED=1
		fi
	done
}

# ensure_php switches on the PHP that came with php-fpm. Debian names its
# Apache configuration after the version (php8.4-fpm.conf), so it is looked up
# instead of guessed.
ensure_php() {
	local f
	PHP_CONF=""
	for f in /etc/apache2/conf-available/php*-fpm.conf; do
		if [ -f "$f" ]; then
			# The newest version wins: the glob comes sorted.
			PHP_CONF="$(basename -- "$f" .conf)"
		fi
	done
	if [ -z "$PHP_CONF" ]; then
		log_error "PHP for Apache was not found (/etc/apache2/conf-available/php*-fpm.conf is missing). Install the package php-fpm and run the setup again."
	fi
	if [ ! -e "/etc/apache2/conf-enabled/${PHP_CONF}.conf" ]; then
		a2enconf -q "$PHP_CONF" || log_error "PHP (${PHP_CONF}) could not be switched on in Apache."
		CHANGED=1
	fi
	systemctl enable --now "${PHP_CONF}.service" ||
		log_error "The service ${PHP_CONF} could not be started."
	log_info "PHP: ${PHP_CONF}"
}

# ensure_site switches our virtual host on and Debian's default site off, so
# no other site answers for this server.
ensure_site() {
	if [ ! -e /etc/apache2/sites-enabled/ngc-web.conf ]; then
		a2ensite -q ngc-web || log_error "The virtual host of NGC could not be switched on."
		CHANGED=1
	fi
	if [ -e /etc/apache2/sites-enabled/000-default.conf ]; then
		a2dissite -q 000-default || log_error "The default site of Apache could not be switched off."
		CHANGED=1
	fi
	if [ "$NGC_CERT_MODE" = letsencrypt ]; then
		if [ ! -e /etc/apache2/conf-enabled/ngc-md.conf ]; then
			a2enconf -q ngc-md || log_error "The settings for Let's Encrypt could not be switched on."
			CHANGED=1
		fi
	elif [ -e /etc/apache2/conf-enabled/ngc-md.conf ]; then
		a2disconf -q ngc-md || log_error "The settings for Let's Encrypt could not be switched off."
		CHANGED=1
	fi
}

# apache_apply tests the configuration and only then reloads Apache. A test
# that fails stops the script, so a running server never takes over a broken
# configuration (shared/ulh.md).
apache_apply() {
	if ! systemctl is-active --quiet apache2; then
		# Apache is not running at all, so a second run of install repairs
		# that too - a stopped web server is not something that is right.
		if ! apachectl configtest; then
			log_error "Apache says these settings are not in order (its message is above). It was not started."
		fi
		systemctl enable --now apache2 || log_error "Apache could not be started."
		log_info "Apache is running, and from now on it starts with the server."
		return 0
	fi
	if [ "$CHANGED" -eq 0 ]; then
		log_info "Nothing changed, Apache stays as it is."
		return 0
	fi
	if ! apachectl configtest; then
		log_error "Apache says these settings are not in order (its message is above). It was not reloaded, so the site keeps running as before."
	fi
	systemctl reload apache2 || log_error "Apache could not be reloaded."
	log_info "Apache has taken the new settings."
}

# ============================================================
# THE CERTIFICATE FOR THE BROWSER
# ============================================================

ensure_cert() {
	case "$NGC_CERT_MODE" in
	selfsigned) ensure_cert_selfsigned ;;
	import) ensure_cert_import ;;
	letsencrypt) ensure_cert_letsencrypt ;;
	esac
}

# cert_fits says whether the certificate that is there still covers the name
# and holds for another month: then a second run leaves it alone.
cert_fits() {
	if [ ! -s "$NGC_CERT" ] || [ ! -s "$NGC_KEY" ]; then
		return 1
	fi
	# 30 days ahead, so a new certificate is never made in a hurry.
	if ! openssl x509 -in "$NGC_CERT" -noout -checkend 2592000 >/dev/null 2>&1; then
		return 1
	fi
	if is_ipv4 "$NGC_HOSTNAME"; then
		openssl x509 -in "$NGC_CERT" -noout -checkip "$NGC_HOSTNAME" >/dev/null 2>&1
	else
		openssl x509 -in "$NGC_CERT" -noout -checkhost "$NGC_HOSTNAME" >/dev/null 2>&1
	fi
}

ensure_cert_selfsigned() {
	local san
	if cert_fits; then
		log_info "The certificate of this server still fits, it stays as it is."
		return 0
	fi
	if is_ipv4 "$NGC_HOSTNAME"; then
		san="IP:${NGC_HOSTNAME}"
	else
		san="DNS:${NGC_HOSTNAME}"
	fi
	# 397 days: browsers refuse a longer one even when it was trusted by hand,
	# and renewing it is one call of "Einrichten" in ulh.
	openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -noenc \
		-days 397 -sha256 -subj "/CN=${NGC_HOSTNAME}" \
		-addext "subjectAltName=${san}" \
		-addext "basicConstraints=critical,CA:FALSE" \
		-addext "keyUsage=critical,digitalSignature,keyAgreement" \
		-addext "extendedKeyUsage=serverAuth" \
		-keyout "${WORK}/web.key" -out "${WORK}/web.crt" >/dev/null 2>&1 ||
		log_error "The certificate could not be made."
	put_file "${WORK}/web.crt" "$NGC_CERT" 0644
	put_file "${WORK}/web.key" "$NGC_KEY" 0600
	# Not in letsencrypt mode: there this certificate is only what the server
	# starts with, and mod_md says what happens after that.
	if [ "$NGC_CERT_MODE" = selfsigned ]; then
		log_warn "This certificate is self-signed, so the browser warns the first time. It holds for 397 days; after that call 'Set up the web interface' in ulh once more."
	fi
}

ensure_cert_import() {
	# -passin pass: instead of a question: Apache starts without anybody at the
	# keyboard, so a key with a password would be no help here either. Only the
	# public part ever leaves openssl, never the key itself.
	if ! openssl pkey -in "$NGC_KEY_FILE" -passin pass: -pubout -out "${WORK}/key.pub" >/dev/null 2>&1; then
		log_error "The key ${NGC_KEY_FILE} cannot be read. Is it protected by a password? Apache cannot use such a key."
	fi
	if ! openssl x509 -in "$NGC_CERT_FILE" -noout -pubkey >"${WORK}/cert.pub" 2>/dev/null; then
		log_error "${NGC_CERT_FILE} is no certificate in PEM form."
	fi
	# Each key on its own into DER and then compared byte for byte: a step that
	# failed must not turn into a match, which it would with a hash over
	# nothing on both sides.
	openssl pkey -pubin -in "${WORK}/cert.pub" -outform DER -out "${WORK}/cert.spki" >/dev/null 2>&1 ||
		log_error "The public key in ${NGC_CERT_FILE} cannot be read."
	openssl pkey -pubin -in "${WORK}/key.pub" -outform DER -out "${WORK}/key.spki" >/dev/null 2>&1 ||
		log_error "The key ${NGC_KEY_FILE} cannot be read."
	if ! cmp -s -- "${WORK}/cert.spki" "${WORK}/key.spki"; then
		log_error "The certificate and the key do not belong together. Check whether you named the right two files."
	fi
	if ! openssl x509 -in "$NGC_CERT_FILE" -noout -checkend 0 >/dev/null 2>&1; then
		log_warn "This certificate has run out. The browser will warn."
	fi
	cp -f -- "$NGC_CERT_FILE" "${WORK}/web.crt"
	cp -f -- "$NGC_KEY_FILE" "${WORK}/web.key"
	put_file "${WORK}/web.crt" "$NGC_CERT" 0644
	put_file "${WORK}/web.key" "$NGC_KEY" 0600
}

ensure_cert_letsencrypt() {
	# mod_md fetches the certificate itself and renews it, and for a managed
	# domain it hands Apache its own instead of the files of the virtual host.
	# The self-signed one is made all the same: with it the server starts and
	# answers right away, and if the certificate from Let's Encrypt does not
	# arrive, the browser warns instead of the site being down.
	ensure_cert_selfsigned
	render_md >"${WORK}/ngc-md.conf"
	put_file "${WORK}/ngc-md.conf" "$MD_FILE" 0644
	log_warn "Let's Encrypt needs ${NGC_HOSTNAME} to point at this server from the internet, and port 80 to be open. Apache fetches the certificate a few minutes after the start. If the browser still warns after that, 'journalctl -u apache2' says why."
}

# ============================================================
# WHAT GETS WRITTEN: THE API TRUST, web.json, APACHE
# ============================================================

# sync_api_trust fetches the certificate of every API, compares its pin with
# the one from the answers and only then writes it into config.APITrustFile.
# A pin that does not match stops the installation: without it the whole
# encryption would be worthless (shared/ulh.md, "TLS intern, nie ungeprueft").
sync_api_trust() {
	local i url hp host port pin want
	: >"${WORK}/trust.pem"
	for i in "${!APIS[@]}"; do
		url="${APIS[$i]}"
		want="${PINS[$i]}"
		hp="${url#https://}"
		host="${hp%:*}"
		port="${hp##*:}"
		log_info "Fetching the certificate of ${url} ..."
		if ! fetch_cert "$host" "$port" "${WORK}/api.pem"; then
			log_error "The API ${url} does not answer with TLS 1.3 and AES-256-GCM. Is ngc-api running there, and is port ${port} open?"
		fi
		pin="$(pin_of_cert "${WORK}/api.pem")" ||
			log_error "The certificate of ${url} could not be read."
		if [ "$pin" != "$want" ]; then
			log_error "The fingerprint of ${url} does not match. Given: ${want} - the API shows: ${pin}. This is where it stops: with a wrong fingerprint the whole encryption would be worthless. Compare it character by character with what ngc-api printed; if it really does not match, the server answering there is not the API you mean."
		fi
		log_info "Fingerprint matches: ${url}"
		cat "${WORK}/api.pem" >>"${WORK}/trust.pem"
	done
	ensure_dir "$NGC_TLS" 0755
	put_file "${WORK}/trust.pem" "$NGC_TRUST" 0644
}

# fetch_cert writes the certificate the API answers with into a file. Nothing
# trusts it yet - the pin decides, right after. TLS 1.3 and the single cipher
# suite are the ones Apache will offer later, so an API that cannot do them
# fails here and not with a 502 in somebody's browser.
fetch_cert() {
	local host="$1" port="$2" out="$3"
	if ! timeout 20 openssl s_client -connect "${host}:${port}" -servername "$host" \
		-tls1_3 -ciphersuites TLS_AES_256_GCM_SHA384 -showcerts \
		</dev/null >"${WORK}/s_client.out" 2>/dev/null; then
		return 1
	fi
	# The first certificate of the answer is the server's own.
	sed -n '/^-----BEGIN CERTIFICATE-----$/,/^-----END CERTIFICATE-----$/p' \
		<"${WORK}/s_client.out" | sed '/^-----END CERTIFICATE-----$/q' >"$out"
	[ -s "$out" ]
}

# render_web_json writes /etc/ngc/web.json (config.Web): strict JSON, never a
# null, and an empty field left out entirely (shared/README.md) - that is why
# "rp" is missing when the server is called by its IP address, where passkeys
# cannot work anyway. Indentation and line breaks are the ones config.SaveWeb
# makes (two spaces, every list on its own lines), because the controller with
# role web writes this same file later and the file should not jump about. The
# example in shared/testdata/config/web.json is formatted by hand and keeps a
# list of one origin on a single line, which Go never does: what the writer
# does decides here, not what the test data look like.
render_web_json() {
	local i last
	printf '{\n  "apis": [\n'
	last=$((${#APIS[@]} - 1))
	for i in "${!APIS[@]}"; do
		printf '    {\n      "url": "%s",\n      "tls": "%s"\n    }' "${APIS[$i]}" "${PINS[$i]}"
		if [ "$i" -lt "$last" ]; then
			printf ',\n'
		else
			printf '\n'
		fi
	done
	printf '  ]'
	if [ -n "$RP_ID" ]; then
		printf ',\n  "rp": {\n    "id": "%s",\n    "origins": [\n      "https://%s"\n    ]\n  }' \
			"$RP_ID" "$RP_ID"
	fi
	printf '\n}\n'
}

# render_balancer writes /etc/ngc/apache-apis.conf (config.BalancerFile), byte
# for byte the template of the NGC repository
# (apps/web/templates/apache-apis.conf.example), with one BalancerMember per
# entry of web.json in the same order. The controller with role web writes
# exactly this form later, so the paths below are spelled out and not built
# from variables.
render_balancer() {
	local u
	printf '%s\n' \
		'# /etc/ngc/apache-apis.conf' \
		'# Written by ngc-web (install, configure) and after that by ngc-controller with' \
		'# role web, both from /etc/ngc/web.json. Never edit by hand; every write is' \
		'# atomic, mode 0644, and Apache is reloaded only after apachectl configtest.' \
		'SSLProxyEngine on' \
		'SSLProxyVerify require' \
		'SSLProxyCACertificateFile /etc/ngc/tls/api-trust.pem' \
		'SSLProxyCheckPeerName on' \
		'SSLProxyCheckPeerExpire on' \
		'SSLProxyProtocol TLSv1.3' \
		'SSLProxyCipherSuite TLSv1.3 TLS_AES_256_GCM_SHA384' \
		'' \
		'<Proxy "balancer://ngc-api">'
	for u in "${APIS[@]}"; do
		printf '    BalancerMember "%s" retry=5 timeout=65 keepalive=On\n' "$u"
	done
	printf '%s\n' \
		'    ProxySet lbmethod=byrequests failontimeout=On' \
		'</Proxy>' \
		'' \
		'ProxyPreserveHost Off' \
		'ProxyPass        "/api/" "balancer://ngc-api/api/" upgrade=websocket' \
		'ProxyPassReverse "/api/" "balancer://ngc-api/api/"'
}

# render_md writes the two lines mod_md needs for Let's Encrypt. MDomain only
# works in the server configuration, so it cannot live in the virtual host.
render_md() {
	printf '%s\n' \
		'# /etc/apache2/conf-available/ngc-md.conf' \
		"# Written by ngc-web: Apache fetches and renews the certificate of" \
		"# ${NGC_HOSTNAME} from Let's Encrypt itself (mod_md)." \
		'# Never edit by hand.' \
		"MDomain ${NGC_HOSTNAME}" \
		'MDCertificateAgreement accepted'
}

# render_site writes the virtual host: HTTPS with TLS 1.3 and AES-256-GCM
# only, the web root is public/ and nothing above it, and /api/ goes to the
# balancer.
render_site() {
	printf '%s\n' \
		'# /etc/apache2/sites-available/ngc-web.conf' \
		'# Written by ngc-web (install, configure). Never edit by hand.' \
		'' \
		'<VirtualHost *:80>' \
		"    ServerName ${NGC_HOSTNAME}" \
		'    RewriteEngine On' \
		"    # mod_md answers Let's Encrypt under /.well-known/acme-challenge/" \
		'    # on this port, so that one path is not redirected.' \
		'    RewriteCond %{REQUEST_URI} !^/\.well-known/acme-challenge/' \
		'    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [R=308,L]' \
		'</VirtualHost>' \
		'' \
		'<VirtualHost *:443>' \
		"    ServerName ${NGC_HOSTNAME}" \
		"    DocumentRoot ${NGC_ROOT}/public" \
		'' \
		'    SSLEngine on' \
		'    SSLProtocol -all +TLSv1.3' \
		'    SSLCipherSuite TLSv1.3 TLS_AES_256_GCM_SHA384' \
		'    SSLHonorCipherOrder on' \
		"    # With Let's Encrypt mod_md hands Apache its own certificate for" \
		'    # this name and these two lines step aside; they are what the' \
		'    # server starts with until then.' \
		"    SSLCertificateFile    ${NGC_CERT}" \
		"    SSLCertificateKeyFile ${NGC_KEY}"
	printf '%s\n' \
		'' \
		'    # The same value the interface sends with every page, so the two' \
		'    # can never disagree; static files get it from here.' \
		'    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains"' \
		'' \
		"    <Directory ${NGC_ROOT}/public>" \
		'        Require all granted' \
		'        Options -Indexes' \
		'        AllowOverride None' \
		'    </Directory>' \
		'' \
		'    # Everything outside /assets/ and /api/ is handed to the single' \
		'    # entry point, so no file that happens to lie in the web root is' \
		'    # ever served or run.' \
		'    RewriteEngine On' \
		'    RewriteCond %{REQUEST_URI} !^/(assets|api)/' \
		'    RewriteRule !^/index\.php$ /index.php [L]' \
		'' \
		'    # The API servers: the balancer and its TLS settings, written from' \
		'    # /etc/ngc/web.json.' \
		"    Include ${NGC_BALANCER}" \
		'' \
		'    ErrorLog ${APACHE_LOG_DIR}/ngc-web-error.log' \
		'    CustomLog ${APACHE_LOG_DIR}/ngc-web-access.log combined' \
		'</VirtualHost>'
}

# ============================================================
# THE ACTIONS
# ============================================================

# configure_all is everything that comes out of the answers: the certificate,
# the trust in the APIs, web.json, the balancer and the virtual host. install
# runs it too, so a second run of install changes nothing that is already right.
configure_all() {
	# 0755: the PHP of the interface runs as the web server's user and has to
	# get through these two folders to web.json and to nothing else. What is
	# secret in them is secret by its own mode - web.key is 0600, and an
	# api.json of another part on the same server stays 0600 as well.
	ensure_dir "$NGC_ETC" 0755
	ensure_dir "$NGC_TLS" 0755
	ensure_cert
	sync_api_trust

	render_web_json >"${WORK}/web.json"
	# web.json holds no secret and the PHP of the interface reads it as the
	# web server's user, so it is 0644 - the mode config.SaveWeb writes, with
	# which the controller with role web writes this same file later.
	put_file "${WORK}/web.json" "$NGC_WEB_JSON" 0644

	render_balancer >"${WORK}/apache-apis.conf"
	put_file "${WORK}/apache-apis.conf" "$NGC_BALANCER" 0644

	render_site >"${WORK}/ngc-web.conf"
	put_file "${WORK}/ngc-web.conf" "$SITE_FILE" 0644

	ensure_modules
	ensure_php
	ensure_site
	apache_apply
}

install_ngc_web() {
	need_root
	need_debian
	work_init
	log_section "Setting up the NGC web interface"
	read_answers
	ensure_packages
	install_release
	configure_all
	show_next_steps
}

configure_ngc_web() {
	need_root
	need_debian
	work_init
	log_section "Changing the settings of the NGC web interface"
	read_answers
	if [ ! -f "${NGC_ROOT}/public/index.php" ]; then
		log_error "There is no web interface in ${NGC_ROOT} yet. Call 'Set up the web interface' first."
	fi
	configure_all
	show_next_steps
}

uninstall_ngc_web() {
	local f
	need_root
	need_debian
	log_section "Removing the NGC web interface"

	if [ -e /etc/apache2/sites-enabled/ngc-web.conf ]; then
		a2dissite -q ngc-web || true
		CHANGED=1
	fi
	if [ -e /etc/apache2/conf-enabled/ngc-md.conf ]; then
		a2disconf -q ngc-md || true
		CHANGED=1
	fi
	rm -f -- "$SITE_FILE" "$MD_FILE"
	rm -rf -- "$NGC_ROOT" "${NGC_ROOT}.new" "${NGC_ROOT}.old"
	rm -f -- "$NGC_BALANCER"
	CHANGED=1
	# Apache itself stays: other sites may use it. ulh removes it with its
	# own entry "apache".
	if systemctl is-active --quiet apache2; then
		if apachectl configtest; then
			systemctl reload apache2 || true
		fi
	fi
	log_info "The virtual host and ${NGC_ROOT} are gone. Apache itself stays installed."

	# Only the files of ngc-web, never the whole /etc/ngc: on a server with
	# several roles api.json, controller.json and trust-anchor.json lie there
	# too and belong to other parts. /var/lib/ngc/release.seq counts for every
	# part, so it stays as well.
	if [ "$NGC_PURGE" = yes ]; then
		for f in "$NGC_WEB_JSON" "$NGC_TRUST" "$NGC_CERT" "$NGC_KEY"; do
			rm -f -- "$f"
		done
		rm -rf -- "$NGC_KEPT"
		log_warn "Deleted: web.json, api-trust.pem and the certificate of the web server."
	else
		# Kept data stays under /var/lib/ngc/, so a new installation finds it
		# again (shared/ulh.md).
		ensure_dir "$NGC_KEPT" 0700
		for f in "$NGC_WEB_JSON" "$NGC_TRUST" "$NGC_CERT" "$NGC_KEY"; do
			if [ -f "$f" ]; then
				cp -p -- "$f" "${NGC_KEPT}/"
			fi
		done
		log_info "Kept: web.json and the certificates stay in ${NGC_ETC}, with a copy of them under ${NGC_KEPT}."
	fi
	log_info "Done."
}

show_next_steps() {
	local scheme_host="https://${NGC_HOSTNAME}"
	printf '\n'
	log_info "Done. What comes next:"
	printf '  1. Open %s in a browser.\n' "$scheme_host"
	printf '  2. Type in the setup code that ngc-api printed at the end on the\n'
	printf '     first API server, and make the first admin account.\n'
	printf '  3. Then pair the controller on this server (ulh, entry\n'
	printf '     ngc-controller). Only it keeps the trust list up to date.\n'
	if [ -z "$RP_ID" ]; then
		printf '\n'
		log_warn "This server is called by an IP address. Passkeys cannot work that way, so logging in runs with a password."
	fi
}

# ============================================================
# MAIN
# ============================================================

case "$ACTION" in
install)
	install_ngc_web
	;;
configure | config)
	configure_ngc_web
	;;
uninstall)
	uninstall_ngc_web
	;;
*)
	# Prints the actions and their parameters from the catalog.
	print_usage ngc-web && exit 1
	;;
esac

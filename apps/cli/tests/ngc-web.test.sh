# ngc-web: what can be checked without a server - the two files it writes for
# Apache and NGC, byte for byte, and which hosts, addresses and fingerprints it
# refuses. Sourced by run.sh.
#
# The functions come out of the script itself, so this tests the file that ships
# and not a copy of it. Each call happens in a subshell, so none of ngc-web's
# functions stays behind in the test shell.

ngcdir="${TMP}/ngc-web"
mkdir -p "$ngcdir"
awk 'f && /^case "\$ACTION" in$/ {exit} /^parse_parameters / {f=1; next} f' \
    "${ULH}/apps/cli/assets/scripts/ngc-web.sh" > "${ngcdir}/body.sh"
check "the functions of ngc-web can be read out of it" grep -q '^render_balancer() {' "${ngcdir}/body.sh"

# ngc_load is the preamble of every call below: bootstrap for the log_* helpers,
# then the body of the script.
ngc_load() {
    # shellcheck disable=SC1090,SC1091
    source "${ULH}/apps/cli/classes/bootstrap.sh"
    source "${ngcdir}/body.sh"
    WORK="${ngcdir}/work"
    mkdir -p "$WORK"
}

# Two APIs, as apps/web/tests/web.json of the NGC repository has them.
API1="https://api-1.ngc.test:7443"
API2="https://api-2.ngc.test:7443"
PIN1="4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eE"
PIN2="4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uI"

ngc_balancer() (
    ngc_load
    APIS=("$@")
    render_balancer
)
ngc_webjson() (
    ngc_load
    APIS=("$API1" "$API2")
    PINS=("$PIN1" "$PIN2")
    RP_ID="$1"
    render_web_json
)
ngc_answers() (
    ngc_load
    APIS=()
    PINS=()
    NGC_HOSTNAME="$1" NGC_CERT_MODE="$2" NGC_APIS="$3" NGC_API_PINS="$4"
    NGC_CERT_FILE="" NGC_KEY_FILE=""
    read_answers > /dev/null 2>&1
)
ngc_host() (
    ngc_load
    valid_host "$1"
)
ngc_site() (
    ngc_load
    NGC_HOSTNAME="ngc.example.org"
    VHOST_TEMPLATE="$1"
    render_site
)
ngc_asset_walls() (
    ngc_load
    asset_walls
)
ngc_template_walls() (
    ngc_load
    template_walls "$1"
)
# ensure_vhost_template ends the script with log_error, so every call runs in
# its own subshell: the exit code is the verdict and the text is the message a
# human reads.
ngc_ensure_tpl() (
    ngc_load
    VHOST_TEMPLATE="$1"
    ensure_vhost_template 2>&1
)
ngc_name_filled() (
    ngc_load
    ensure_name_filled "$1" 2>&1
)
ngc_keep_site() (
    ngc_load
    SITE_FILE="$1"
    SITE_KEPT="${1}.before-ulh"
    keep_foreign_site 2>&1
)

# ---------------------------------------------------------------- the balancer
# config.BalancerFile of NGC. This is the template of the NGC repository
# (apps/web/templates/apache-apis.conf.example), which the controller with role
# web writes byte for byte as well: changes there belong here too.
cat > "${ngcdir}/balancer.want" <<'EOF'
# /etc/ngc/apache-apis.conf
# Written by ngc-web (install, configure) and after that by ngc-controller with
# role web, both from /etc/ngc/web.json. Never edit by hand; every write is
# atomic, mode 0644, and Apache is reloaded only after apachectl configtest.
SSLProxyEngine on
SSLProxyVerify require
SSLProxyCACertificateFile /etc/ngc/tls/api-trust.pem
SSLProxyCheckPeerName on
SSLProxyCheckPeerExpire on
SSLProxyProtocol TLSv1.3
SSLProxyCipherSuite TLSv1.3 TLS_AES_256_GCM_SHA384

<Proxy "balancer://ngc-api">
    BalancerMember "https://api-1.ngc.test:7443" retry=5 timeout=65 keepalive=On
    BalancerMember "https://api-2.ngc.test:7443" retry=5 timeout=65 keepalive=On
    ProxySet lbmethod=byrequests failontimeout=On
</Proxy>

ProxyPreserveHost Off
ProxyPass        "/api/" "balancer://ngc-api/api/" upgrade=websocket
ProxyPassReverse "/api/" "balancer://ngc-api/api/"
EOF
ngc_balancer "$API1" "$API2" > "${ngcdir}/balancer.got"
check "balancer for Apache: byte for byte the form of the contract" \
    cmp -s "${ngcdir}/balancer.want" "${ngcdir}/balancer.got"
check "one API gives one BalancerMember" \
    test "$(ngc_balancer "$API1" | grep -c BalancerMember)" = 1
# The path of the trust file stands written out in the balancer, because the
# form is fixed; it has to be the one the script itself writes.
check "the balancer names the trust file the script writes" \
    test "$(grep -c "^SSLProxyCACertificateFile $(grep -m1 '^NGC_TRUST=' "${ngcdir}/body.sh" | cut -d'"' -f2)\$" \
        "${ngcdir}/balancer.got")" = 1

# ---------------------------------------------------------------- web.json
# config.Web, in the shape config.SaveWeb writes (Go's json.Indent, two spaces).
cat > "${ngcdir}/web.want" <<'EOF'
{
  "apis": [
    {
      "url": "https://api-1.ngc.test:7443",
      "tls": "4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eE"
    },
    {
      "url": "https://api-2.ngc.test:7443",
      "tls": "4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uI"
    }
  ],
  "rp": {
    "id": "ngc.example.org",
    "origins": [
      "https://ngc.example.org"
    ]
  }
}
EOF
ngc_webjson "ngc.example.org" > "${ngcdir}/web.got"
check "web.json: byte for byte the shape of config.SaveWeb" \
    cmp -s "${ngcdir}/web.want" "${ngcdir}/web.got"
# Passkeys need a name, so rp is left out for an IP address.
check "web.json without a name carries no rp" \
    not grep -q '"rp"' <(ngc_webjson "")

# ---------------------------------------------------------------- the answers
good=0
while IFS='|' read -r label host mode apis pins; do
    [[ -n "$label" ]] || continue
    ngc_answers "$host" "$mode" "$apis" "$pins" || { good=$((good + 1)); echo "    refused: ${label}"; }
done <<EOF
name|ngc.example.org|selfsigned|${API1}|${PIN1}
IP address|192.168.1.10|selfsigned|${API1}|${PIN1}
two APIs|ngc.example.org|selfsigned|${API1} ${API2}|${PIN1} ${PIN2}
Let's Encrypt for a name|ngc.example.org|letsencrypt|${API1}|${PIN1}
EOF
check "ngc-web takes the answers that are in order" test "$good" = 0

bad=0
while IFS='|' read -r label host mode apis pins; do
    [[ -n "$label" ]] || continue
    if ngc_answers "$host" "$mode" "$apis" "$pins"; then
        bad=$((bad + 1)); echo "    taken: ${label}"
    fi
done <<EOF
host in capitals|NGC.example.org|selfsigned|${API1}|${PIN1}
host with a space|ngc example.org|selfsigned|${API1}|${PIN1}
host as IPv6|[2001:db8::1]|selfsigned|${API1}|${PIN1}
no host||selfsigned|${API1}|${PIN1}
unknown way to a certificate|ngc.example.org|certbot|${API1}|${PIN1}
Let's Encrypt for an IP address|192.168.1.10|letsencrypt|${API1}|${PIN1}
import without the files|ngc.example.org|import|${API1}|${PIN1}
no API at all|ngc.example.org|selfsigned||
API without a port|ngc.example.org|selfsigned|https://api-1.ngc.test|${PIN1}
API with a path|ngc.example.org|selfsigned|${API1}/api|${PIN1}
API over plain http|ngc.example.org|selfsigned|http://api-1.ngc.test:7443|${PIN1}
API on port 0|ngc.example.org|selfsigned|https://api-1.ngc.test:0|${PIN1}
API on port 99999|ngc.example.org|selfsigned|https://api-1.ngc.test:99999|${PIN1}
one fingerprint too many|ngc.example.org|selfsigned|${API1}|${PIN1} ${PIN2}
one fingerprint too few|ngc.example.org|selfsigned|${API1} ${API2}|${PIN1}
the same API twice|ngc.example.org|selfsigned|${API1} ${API1}|${PIN1} ${PIN2}
fingerprint too short|ngc.example.org|selfsigned|${API1}|abc
fingerprint with a plus|ngc.example.org|selfsigned|${API1}|4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4+E
EOF
check "ngc-web refuses every answer that is not in order" test "$bad" = 0

# Nothing a shell would read as a command may pass as a host: it would end up in
# Apache's configuration.
shell=0
for h in 'a;id' '$(id)' '`id`' 'a b' 'a|b' 'a>b' "a'b" 'a"b' '*' '-a'; do
    if ngc_host "$h"; then shell=$((shell + 1)); echo "    taken: ${h}"; fi
done
check "ngc-web refuses hosts with shell characters" test "$shell" = 0

# ------------------------------------------------- the walls of the virtual host
# The files below /assets/ are handed out by Apache, so no PHP of the interface
# ever sees those answers and their headers have to stand in the virtual host.
# This is the hole that was here before: /assets/ used to be taken out of a
# rewrite, so a MISSING file there was answered by Apache with no header at all.
#
# There is ONE version of those walls now, and it is NGC's: the script writes
# the template of the release with the name of this server filled in. The file
# below stands in for that template - it cannot be the real one, which lives in
# the NGC repository, so every path in it comes out of this script's own
# constants and cannot drift away from them unnoticed.
ngcroot="$(grep -m1 '^NGC_ROOT=' "${ngcdir}/body.sh" | cut -d'"' -f2)"
ngccert="$(grep -m1 '^NGC_CERT=' "${ngcdir}/body.sh" | cut -d'"' -f2)"
ngckey="$(grep -m1 '^NGC_KEY=' "${ngcdir}/body.sh" | cut -d'"' -f2)"
ngcbal="$(grep -m1 '^NGC_BALANCER=' "${ngcdir}/body.sh" | cut -d'"' -f2)"
cat > "${ngcdir}/tpl.conf" <<EOF
# The Apache virtual host of the NGC web interface.
<VirtualHost *:80>
    ServerName NGC-HOSTNAME
    DocumentRoot "/var/www/html"
    RewriteEngine On
    RewriteCond %{REQUEST_URI} !^/\\.well-known/acme-challenge/
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [R=308,L]
</VirtualHost>

<VirtualHost *:443>
    ServerName NGC-HOSTNAME
    SSLEngine on
    SSLCertificateFile    ${ngccert}
    SSLCertificateKeyFile ${ngckey}
    SSLProtocol -all +TLSv1.3
    ServerSignature Off
    DocumentRoot "${ngcroot}/public"
    <Directory "${ngcroot}">
        Require all denied
        AllowOverride None
        Options None
    </Directory>
    <Directory "${ngcroot}/public">
        Require all granted
        AllowOverride None
        Options -Indexes -FollowSymLinks -ExecCGI -Includes
        FallbackResource /index.php
    </Directory>
    <Directory "${ngcroot}/public/assets">
        Header always set X-Content-Type-Options "nosniff"
        Header always set Cross-Origin-Resource-Policy "same-origin"
        Header always set Content-Security-Policy "default-src 'none'; script-src 'self'"
        Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains"
    </Directory>
    Include ${ngcbal}
</VirtualHost>
EOF
check "the stand-in template is one this script accepts" \
    ngc_ensure_tpl "${ngcdir}/tpl.conf"

ngc_site "${ngcdir}/tpl.conf" > "${ngcdir}/site.got"
sed 's/NGC-HOSTNAME/ngc.example.org/g' "${ngcdir}/tpl.conf" > "${ngcdir}/tpl.filled"
# Everything after the header of the script has to be the template, byte for
# byte. The header is counted and not guessed, so a line added to it does not
# quietly make this comparison compare less.
hdr=$(( $(grep -c '' "${ngcdir}/site.got") - $(grep -c '' "${ngcdir}/tpl.filled") ))
head -n "$hdr" "${ngcdir}/site.got" > "${ngcdir}/site.head"
tail -n +$((hdr + 1)) "${ngcdir}/site.got" > "${ngcdir}/site.body"
check "the virtual host is the template of the release, byte for byte" \
    cmp -s "${ngcdir}/tpl.filled" "${ngcdir}/site.body"
check "and the script adds nothing to it but comments" \
    test "$(grep -c '^#' "${ngcdir}/site.head")" = "$hdr"
check "whose first line names the file, so keep_foreign_site knows it again" \
    grep -qxF "# $(grep -m1 '^SITE_FILE=' "${ngcdir}/body.sh" | cut -d'"' -f2)" \
        <(head -n 1 "${ngcdir}/site.head")
# The one value that is filled in. A placeholder left standing would make
# Apache answer under the name of whoever wrote the template.
check "no placeholder for the name is left in the virtual host" \
    not grep -q 'NGC-HOSTNAME' "${ngcdir}/site.got"
check "and the script refuses a file that still has one" \
    not ngc_name_filled "${ngcdir}/tpl.conf"
check "whose message says the name could not be filled in" \
    grep -q 'could not be filled into' <(ngc_name_filled "${ngcdir}/tpl.conf")
check "while the file it wrote passes that same check" \
    ngc_name_filled "${ngcdir}/site.got"
check "both virtual hosts answer to the name that was answered" \
    test "$(grep -c '^    ServerName ngc.example.org$' "${ngcdir}/site.got")" = 2

# Four headers have to reach an answer below /assets/, and they stand in the
# assets block of the template.
sed -n "\\#^    <Directory \"${ngcroot}/public/assets\">\$#,\\#^    </Directory>\$#p" \
    "${ngcdir}/site.got" | grep -E '^        Header always set ' |
    sed -E 's/^ *Header always set ([A-Za-z-]+) "(.*)"$/\1 \2/' | sort > "${ngcdir}/walls.site"
ngc_asset_walls > "${ngcdir}/walls.list"
check "every wall of asset_walls really stands in the virtual host" \
    cmp -s "${ngcdir}/walls.list" "${ngcdir}/walls.site"
check "there are four of them" test "$(grep -c . "${ngcdir}/walls.site")" = 4
# Each one by name, so a missing line names itself instead of only moving a count.
for w in X-Content-Type-Options Cross-Origin-Resource-Policy \
         Content-Security-Policy Strict-Transport-Security; do
    check "an answer below /assets/ carries ${w}" grep -q "^${w} " "${ngcdir}/walls.site"
done
# The one that is the opposite of obvious: without script-src 'self' the module
# worker that holds the typed password does not run on WebKit, so no password
# login works in Safari. The NGC repository measured that on both engines.
check "the policy of the asset files keeps the password worker working" \
    grep -qF "Content-Security-Policy default-src 'none'; script-src 'self'" "${ngcdir}/walls.site"

# A missing file below /assets/ has to reach the single entry point, which then
# answers 404 with all the headers of the interface. That is FallbackResource;
# the rewrite that used to stand here let Apache answer such a path itself.
check "the web root routes with FallbackResource" \
    grep -q '^        FallbackResource /index.php$' "${ngcdir}/site.got"
check "nothing takes /assets/ out of the routing any more" \
    not grep -q 'REQUEST_URI} !\^/(assets' "${ngcdir}/site.got"
# FallbackResource comes with mod_dir. Without the module Apache refuses the
# whole file, so the module list has to name it.
check "the module list names dir, which brings FallbackResource" \
    grep -qE '^NGC_MODULES=\(.*\bdir\b' "${ngcdir}/body.sh"
# Everything beside public/ is denied a second time, which survives a typo in
# DocumentRoot.
check "everything beside public/ is denied as well" \
    grep -q "^    <Directory \"${ngcroot}\">\$" "${ngcdir}/site.got"
check "and it is denied, not granted" \
    test "$(sed -n "\\#^    <Directory \"${ngcroot}\">\$#,\\#^    </Directory>\$#p" "${ngcdir}/site.got" |
        grep -c '^        Require all denied$')" = 1

# ------------------------------------- a template this script must NOT pass on
# Every case below ENDS the setup. Nothing is written then: a server that runs
# keeps the virtual host it has, and the message says what to do.
#
# 1 No file at all - a release older than the packer that puts it in.
check "a release without the file is refused" \
    not ngc_ensure_tpl "${ngcdir}/not-here.conf"
check "and the message names the missing file and the way out" \
    grep -q 'does not bring the Apache settings' <(ngc_ensure_tpl "${ngcdir}/not-here.conf")
# 2 A wall is missing. Installing that in silence is how the hole came to be.
grep -v 'Cross-Origin-Resource-Policy' "${ngcdir}/tpl.conf" > "${ngcdir}/tpl-short.conf"
check "a template with one wall fewer is refused" \
    not ngc_ensure_tpl "${ngcdir}/tpl-short.conf"
check "and the message names the wall that is missing" \
    grep -q "do not carry the protective setting 'Cross-Origin-Resource-Policy same-origin'" \
        <(ngc_ensure_tpl "${ngcdir}/tpl-short.conf")
# A Header line the reader does not understand must not become a silent match.
sed 's/"nosniff"/nosniff/' "${ngcdir}/tpl.conf" > "${ngcdir}/tpl-odd.conf"
check "a Header line it cannot read ends template_walls with 1" \
    not ngc_template_walls "${ngcdir}/tpl-odd.conf"
check "and it is refused instead of being called complete" \
    grep -q 'could not be read line by line' <(ngc_ensure_tpl "${ngcdir}/tpl-odd.conf")
# One wall MORE is not refused: NGC may add one, and this script must not be in
# the way of that. It is said out loud, and the setup goes on.
sed "\\#^        Header always set X-Content-Type-Options#a\\        Header always set Referrer-Policy \"no-referrer\"" \
    "${ngcdir}/tpl.conf" > "${ngcdir}/tpl-more.conf"
check "a template with one wall more is taken" ngc_ensure_tpl "${ngcdir}/tpl-more.conf"
check "and says that it brings five" \
    grep -q 'brings 5 protective settings' <(ngc_ensure_tpl "${ngcdir}/tpl-more.conf")
# 3 Other paths: a template built for a different web root would hand out a
# tree nobody here set up.
for part in "DocumentRoot \"${ngcroot}/public\"|the web root" \
            "<Directory \"${ngcroot}\">|the folder above it" \
            "<Directory \"${ngcroot}/public/assets\">|the assets block" \
            "SSLCertificateFile    ${ngccert}|the certificate" \
            "Include ${ngcbal}|the balancer" \
            "FallbackResource /index.php|the routing"; do
    grep -vF "${part%%|*}" "${ngcdir}/tpl.conf" > "${ngcdir}/tpl-path.conf"
    check "a template without ${part##*|} is refused" \
        not ngc_ensure_tpl "${ngcdir}/tpl-path.conf"
done
check "and the message says it was made for another server" \
    grep -q 'made for a different server' \
        <(grep -vF "Include ${ngcbal}" "${ngcdir}/tpl.conf" > "${ngcdir}/tpl-path.conf"
          ngc_ensure_tpl "${ngcdir}/tpl-path.conf")
# 4 The name has to be open, twice: port 80 and port 443.
sed '0,/^    ServerName NGC-HOSTNAME$/s//    ServerName ngc.somebody.else/' \
    "${ngcdir}/tpl.conf" > "${ngcdir}/tpl-name.conf"
check "a template that leaves the name open only once is refused" \
    not ngc_ensure_tpl "${ngcdir}/tpl-name.conf"
check "and the message says the name cannot be filled in" \
    grep -q 'do not leave the name of the server open twice' \
        <(ngc_ensure_tpl "${ngcdir}/tpl-name.conf")

# ------------------------------------------- a virtual host written by somebody
# The script writes this file on every install and configure. A server somebody
# hardened by hand must not lose that work without a word.
printf '# hand written\n<VirtualHost *:443>\n</VirtualHost>\n' > "${ngcdir}/foreign.conf"
check "a virtual host of somebody else is kept and named" \
    grep -q 'did not write' <(ngc_keep_site "${ngcdir}/foreign.conf")
check "and its copy is really there" test -f "${ngcdir}/foreign.conf.before-ulh"
# Our own file carries its own name in the first line, so it is replaced in
# silence - that is what "Never edit by hand" in the second line says.
sed "1s|.*|# ${ngcdir}/own.conf|" "${ngcdir}/site.got" > "${ngcdir}/own.conf"
check "the script says nothing about a file it wrote itself" \
    test -z "$(ngc_keep_site "${ngcdir}/own.conf")"
check "and keeps no copy of it" not test -e "${ngcdir}/own.conf.before-ulh"


# ================================================================ PART TWO
# What the script promised and nothing held it to. Everything above measures
# the two files it writes for Apache and the answers it takes; everything below
# was only written down - in the script's own comments - until 13.10.2026.
#
# A chown this suite cannot do: it runs as a normal user, so "chown root:root"
# fails and would turn every put_file into a log_error. The stub below writes
# down what it was asked for, so the owner is still MEASURED - out of the
# record instead of out of the file system. Nothing else is stubbed away:
# chmod, mv, cmp, tar and openssl all run for real.
ngcbin="${ngcdir}/bin"
mkdir -p "$ngcbin"
cat > "${ngcbin}/chown" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${NGC_CHOWN_LOG:-/dev/null}"
exit 0
STUB
cat > "${ngcbin}/curl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" > "${NGC_CURL_LOG:-/dev/null}"
exit 0
STUB
cat > "${ngcbin}/a2enmod" <<'STUB'
#!/bin/bash
printf '%s\n' "${@: -1}" >> "${NGC_MOD_LOG:-/dev/null}"
exit 0
STUB
cat > "${ngcbin}/apachectl" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$ngcbin"/*

ngc_env() {
    export PATH="${ngcbin}:${PATH}"
    export NGC_CHOWN_LOG="${1:-/dev/null}"
}

# ---------------------------------------------------------------- is_ipv4
# It decides three things at once: whether Let's Encrypt is refused, whether
# the certificate gets an IP or a DNS name in its SAN, and whether rp reaches
# web.json. A name taken for an address would put IP: in front of a DNS name.
ngc_is_ipv4() (
    ngc_load
    is_ipv4 "$1"
)
check "is_ipv4: 192.168.1.10 is an address" ngc_is_ipv4 192.168.1.10
check "is_ipv4: ngc.example.org is not" not ngc_is_ipv4 ngc.example.org
# The trap of the rule "the last label is all digits": a name may well end in
# a number, and 7443.example.org is a name, not an address.
check "is_ipv4: a name whose FIRST label is digits is not an address" \
    not ngc_is_ipv4 7443.example.org
check "is_ipv4: a single number is one" ngc_is_ipv4 10
check "is_ipv4: nothing is not" not ngc_is_ipv4 ""

# ------------------------------------------------- ports, addresses, fingerprints
# read_answers is measured above through its whole chain; these three are the
# grammar underneath it, where the edges live.
ngc_port() (
    ngc_load
    valid_port "$1"
)
ngc_url() (
    ngc_load
    valid_web_url "$1"
)
ngc_pin() (
    ngc_load
    valid_pin "$1"
)
check "port: 7443" ngc_port 7443
check "port: 1 and 65535" ngc_port 1
check "port: 65536 is refused" not ngc_port 65536
check "port: a leading zero is refused" not ngc_port 07443
check "port: 0 is refused" not ngc_port 0
check "port: a sign is refused" not ngc_port "+443"
check "port: six digits are refused" not ngc_port 123456

check "address: https with a name and a port" ngc_url "https://api-1.ngc.test:7443"
check "address: an IPv4 address and a port" ngc_url "https://192.168.1.20:7443"
check "address: without a port is refused" not ngc_url "https://api-1.ngc.test"
check "address: http is refused" not ngc_url "http://api-1.ngc.test:7443"
check "address: wss is refused" not ngc_url "wss://api-1.ngc.test:7443"
check "address: a path at the end is refused" not ngc_url "https://api-1.ngc.test:7443/api"
check "address: a user in front is refused" not ngc_url "https://u@api-1.ngc.test:7443"
check "address: IPv6 in brackets is refused" not ngc_url "https://[2001:db8::1]:7443"
# 256 bytes is the limit of trust.ValidWebURL. The name below is 251 bytes and
# every label of it is one valid_host takes, so the LENGTH OF THE ADDRESS is
# the only thing that can decide here - which the control check right after
# proves.
lab="$(printf 'a%.0s' $(seq 1 62))"
long="${lab}.${lab}.${lab}.${lab}"
check "address: the host of that address is one valid_host takes" ngc_host "$long"
check "address: longer than 256 bytes is refused" not ngc_url "https://${long}:7443"

check "fingerprint: the 43 characters ngc-api prints" ngc_pin "$PIN1"
check "fingerprint: 42 characters are refused" not ngc_pin "${PIN1%?}"
check "fingerprint: 44 characters are refused" not ngc_pin "${PIN1}A"
check "fingerprint: a slash is refused" not ngc_pin "${PIN1%?}/"
check "fingerprint: padding is refused" not ngc_pin "${PIN1%?}="
check "fingerprint: nothing is refused" not ngc_pin ""

# At most 16 API servers; the seventeenth is refused instead of ending up in
# Apache's balancer.
many_u=""; many_p=""
for i in $(seq 1 17); do
    many_u="${many_u}https://api-${i}.ngc.test:7443 "
    many_p="${many_p}$(printf '%s' "$PIN1" | sed "s/.\$/$((i % 10))/") "
done
check "answers: 16 API servers are taken" \
    ngc_answers ngc.example.org selfsigned \
        "$(printf '%s' "$many_u" | cut -d' ' -f1-16)" \
        "$(printf '%s' "$many_p" | cut -d' ' -f1-16)"
check "answers: the seventeenth API server is refused" \
    not ngc_answers ngc.example.org selfsigned "$many_u" "$many_p"

# ------------------------------------------------------------- check_import_file
# The way "import" is the one where the admin names two paths, so a typo has to
# be caught here and not by Apache's log.
ngc_import() (
    ngc_load
    # In the folder where the file below really lies, so the missing / in
    # front is the ONLY thing that can decide about it.
    cd "$ngcdir" || return 1
    check_import_file "$1" certificate > /dev/null 2>&1
)
printf 'x\n' > "${ngcdir}/some.pem"
check "import: an absolute readable file is taken" ngc_import "${ngcdir}/some.pem"
# A path that depends on where ulh was started from is not a path: the file
# below IS there under that name, and it is refused all the same.
check "import: a relative path to a file that is really there is refused" \
    not ngc_import "some.pem"
check "import: a file that is not there is refused" not ngc_import "${ngcdir}/no-such.pem"
check "import: a folder is refused" not ngc_import "${ngcdir}"
check "import: nothing is refused" not ngc_import ""

# ------------------------------------------------------------------- b64url
# The strict base64url of enc.B64, and the one place where "strict" earns its
# keep: a release.json whose payload has a second spelling must not decode, or
# the bytes the signature covers are not the bytes that were read.
ngc_b64url() (
    ngc_load
    printf '%s' "$1" | b64url
)
check "b64url: aGk is hi" test "$(ngc_b64url aGk)" = hi
check "b64url: a trailing newline is allowed" test "$(printf 'aGk\n' | (ngc_load; b64url))" = hi
check "b64url: padding is refused" not ngc_b64url "aGk="
check "b64url: a plus is refused" not ngc_b64url "aG+k"
check "b64url: a slash is refused" not ngc_b64url "aG/k"
# aGl, aGm and aGn all decode to "hi" as well - they differ from aGk only in
# the two bits nobody uses. Only aGk is the encoding of those bytes, and a
# release.json whose payload carries a second spelling must not decode: the
# bytes the signature covers would not be the bytes that were read.
#
# MEASURED on 13.10.2026: it is NOT this script that refuses them here. GNU
# coreutils' base64 -d already says "invalid input" for a trailing bit that
# is not zero, so b64url's own check (the re-encode over b64.again) never
# sees the input, and taking that check out of the script leaves all three
# cases below green. It earns its keep on a base64 that is more forgiving -
# busybox is one - and there it is untested. These three measure the outcome,
# not that line.
for nc in aGl aGm aGn; do
    check "b64url: ${nc} is a second spelling of hi and is refused" not ngc_b64url "$nc"
done
check "NOT MEASURED: b64url's own check of the single spelling - GNU base64 refuses these inputs before it reaches them" false
check "b64url: one character over is refused" not ngc_b64url "a"
check "b64url: a space is refused" not ngc_b64url "aG k"

# -------------------------------------------------------------------- put_file
# A second run of install must change nothing that is already right, and Apache
# is reloaded only when something really changed. Both hang on this function.
ngc_put() (
    ngc_load
    ngc_env "${ngcdir}/chown.log"
    CHANGED=0
    put_file "$1" "$2" "$3" > "${ngcdir}/put.out" 2>&1 || return 1
    printf '%s %s\n' "$CHANGED" "$(stat -c %a "$2")"
)
putdir="${ngcdir}/put"
mkdir -p "$putdir"
printf 'one\n' > "${putdir}/src"
: > "${ngcdir}/chown.log"
check "put_file: writes the file, with the mode it was given, and says so" \
    test "$(ngc_put "${putdir}/src" "${putdir}/dst" 0600)" = "1 600"
# The owner is asked for on the TEMPORARY file, before the rename: that is
# what makes the file root's from the first moment it has a name Apache reads.
check "put_file: and asks for root:root, on the file before the rename"     grep -qE '^root:root -- .*/dst\.[A-Za-z0-9]{6}$' "${ngcdir}/chown.log"
check "put_file: a second time with the same bytes changes nothing" \
    test "$(ngc_put "${putdir}/src" "${putdir}/dst" 0600)" = "0 600"
check "put_file: and says unchanged" grep -q 'unchanged:' "${ngcdir}/put.out"
printf 'two\n' > "${putdir}/src2"
check "put_file: other bytes are written and counted again" \
    test "$(ngc_put "${putdir}/src2" "${putdir}/dst" 0644)" = "1 644"
check "put_file: the bytes that arrived are the bytes of the source" \
    cmp -s "${putdir}/src2" "${putdir}/dst"
# The file is written next to the old one and renamed, so nobody reads half of
# it - and nothing of that may stay lying about, where the next run would find
# it again.
check "put_file: no half file is left next to it" \
    test "$(find "$putdir" -name 'dst.??????' | wc -l)" = 0

# ----------------------------------------------------------------- ensure_dir
ngc_dir() (
    ngc_load
    ngc_env "${ngcdir}/chown.log"
    ensure_dir "$1" "$2" > /dev/null 2>&1 || return 1
    stat -c %a "$1"
)
check "ensure_dir: makes it with the mode of the contract" \
    test "$(ngc_dir "${ngcdir}/d1/d2" 0755)" = 755
check "ensure_dir: 0700 for what uninstall keeps" \
    test "$(ngc_dir "${ngcdir}/d3" 0700)" = 700
check "ensure_dir: an existing folder gets the mode too" \
    test "$(ngc_dir "${ngcdir}/d3" 0755)" = 755

# ------------------------------------------------------------- unpack_release
# Safe unpacking of NGC (shared/README.md): no absolute path, no "..", no
# links, no device files. The interface is plain files and folders, so anything
# else means the archive is not the one NGC builds. This is the one place where
# a signed-but-wrong archive would reach the file system.
ngc_unpack() (
    ngc_load
    NGC_ROOT="${ngcdir}/root"
    unpack_release "$1" 2>&1
)
tardir="${ngcdir}/tar"
mkdir -p "${tardir}/build/public"
printf '<?php\n' > "${tardir}/build/public/index.php"
printf 'body{}\n' > "${tardir}/build/public/assets/app.css" 2>/dev/null ||
    { mkdir -p "${tardir}/build/public/assets"; printf 'body{}\n' > "${tardir}/build/public/assets/app.css"; }
( cd "${tardir}/build" && tar cf "${tardir}/good.tar" . )
rm -rf "${ngcdir}/root"
check "unpack: the archive NGC builds goes in" ngc_unpack "${tardir}/good.tar" > /dev/null
check "unpack: public/index.php is there afterwards" test -f "${ngcdir}/root/public/index.php"
check "unpack: its folders are 0755" test "$(stat -c %a "${ngcdir}/root/public")" = 755
check "unpack: its files are 0644" test "$(stat -c %a "${ngcdir}/root/public/index.php")" = 644
check "unpack: nothing of the unpacking is left beside it" \
    test "$(ls -d "${ngcdir}/root".new "${ngcdir}/root".old 2>/dev/null | wc -l)" = 0

# An absolute path: with tar -P it stays in the archive, and that is exactly
# the archive this guard is for.
mkdir -p "${tardir}/abs"
printf 'x\n' > "${tardir}/abs/pw"
( cd "${tardir}/abs" && tar -P -cf "${tardir}/abs.tar" "${tardir}/abs/pw" )
check "unpack: an absolute path is refused" not ngc_unpack "${tardir}/abs.tar"
check "unpack: and it says the path leads out of the folder" \
    grep -q 'leads out of the target folder' <(ngc_unpack "${tardir}/abs.tar")
# "..": the classic way out of the target folder.
mkdir -p "${tardir}/up/public"
printf '<?php\n' > "${tardir}/up/public/index.php"
# GNU tar normalises a path it is given, so the ".." is put into the member
# name instead: this is the archive the guard is for, not one tar would build
# by accident.
( cd "${tardir}/up" && tar cf "${tardir}/up.tar"     --transform='s|^public/|../public/|' public/index.php )
check "unpack: a path with .. in it is refused" not ngc_unpack "${tardir}/up.tar"
# A link would hand out whatever it points at, under the web root.
mkdir -p "${tardir}/lnk/public"
printf '<?php\n' > "${tardir}/lnk/public/index.php"
ln -sf /etc/passwd "${tardir}/lnk/public/pw"
( cd "${tardir}/lnk" && tar cf "${tardir}/lnk.tar" . )
check "unpack: a symbolic link is refused" not ngc_unpack "${tardir}/lnk.tar"
check "unpack: and it says links or device files" \
    grep -q 'links or device files' <(ngc_unpack "${tardir}/lnk.tar")
# An archive without the single entry point is not the web interface.
mkdir -p "${tardir}/nophp/public"
printf 'x\n' > "${tardir}/nophp/public/other.php"
( cd "${tardir}/nophp" && tar cf "${tardir}/nophp.tar" . )
check "unpack: an archive without public/index.php is refused" \
    not ngc_unpack "${tardir}/nophp.tar"
check "unpack: and the folder it had begun is gone again" \
    not test -e "${ngcdir}/root.new"
printf 'not a tar at all\n' > "${tardir}/junk.tar"
check "unpack: something that is no archive is refused" not ngc_unpack "${tardir}/junk.tar"
# The one that matters after all the refusals: the web interface that was
# already there is still there. Each case above ran against the good unpack.
check "unpack: a refused archive leaves the interface that was there alone" \
    test -f "${ngcdir}/root/public/index.php"

# --------------------------------------------------------------------- render_md
ngc_md() (
    ngc_load
    NGC_HOSTNAME="$1"
    render_md
)
cat > "${ngcdir}/md.want" <<'EOF'
# /etc/apache2/conf-available/ngc-md.conf
# Written by ngc-web: Apache fetches and renews the certificate of
# ngc.example.org from Let's Encrypt itself (mod_md).
# Never edit by hand.
MDomain ngc.example.org
MDCertificateAgreement accepted
EOF
ngc_md ngc.example.org > "${ngcdir}/md.got"
check "ngc-md.conf: byte for byte what mod_md needs" \
    cmp -s "${ngcdir}/md.want" "${ngcdir}/md.got"
check "ngc-md.conf: the agreement is accepted, or mod_md asks nobody" \
    grep -qx 'MDCertificateAgreement accepted' "${ngcdir}/md.got"

# ------------------------------------------------------------------ the modules
# mod_md is switched on in that one mode and in no other: a managed domain on a
# server with a self-signed certificate would have Apache knock at Let's
# Encrypt for a name that points nowhere.
ngc_mods() (
    ngc_load
    ngc_env
    export NGC_MOD_LOG="$2"
    NGC_CERT_MODE="$1"
    ensure_modules > /dev/null 2>&1
)
: > "${ngcdir}/mods.le"; ngc_mods letsencrypt "${ngcdir}/mods.le"
: > "${ngcdir}/mods.ss"; ngc_mods selfsigned "${ngcdir}/mods.ss"
check "modules: with Let's Encrypt md is switched on" grep -qx md "${ngcdir}/mods.le"
check "modules: self-signed does not switch md on" not grep -qx md "${ngcdir}/mods.ss"
for m in ssl proxy_http proxy_wstunnel proxy_balancer proxy_fcgi dir; do
    check "modules: ${m} is switched on" grep -qx "$m" "${ngcdir}/mods.ss"
done

# -------------------------------------------------------------------- download
# The address of a release carries no trust - the signature does. What this
# call has to keep is narrower: HTTPS and nothing else, not even after a
# redirect, and a size somebody cannot grow without end.
ngc_download() (
    ngc_load
    ngc_env
    export NGC_CURL_LOG="${ngcdir}/curl.args"
    download "https://example.invalid/r.tar" "${ngcdir}/r.tar" > /dev/null 2>&1
    cat "${ngcdir}/curl.args"
)
args="$(ngc_download)"
check "download: only https" grep -q -- "--proto =https" <<< "$args"
check "download: a redirect to anything else is not followed" \
    grep -q -- "--proto-redir =https" <<< "$args"
check "download: at most 256 MB" grep -q -- "--max-filesize 268435456" <<< "$args"
check "download: an error is an error, not an HTML page" grep -q -- "--fail" <<< "$args"
check "download: the address comes after --, so no answer can be an option" \
    grep -q -- "-- https://example.invalid/r.tar" <<< "$args"

# ----------------------------------------------------- the browser certificate
# openssl is on this machine, so these ran for real. A case that cannot run
# says so out loud below instead of skipping itself.
if command -v openssl > /dev/null 2>&1; then
    certdir="${ngcdir}/cert"
    mkdir -p "$certdir"
    ngc_self() (
        ngc_load
        ngc_env
        NGC_HOSTNAME="$1" NGC_CERT_MODE="$2"
        NGC_CERT="${3}/web.crt" NGC_KEY="${3}/web.key"
        CHANGED=0
        ensure_cert_selfsigned > "${3}/out" 2>&1 || return 1
        printf '%s\n' "$CHANGED"
    )
    ngc_fits() (
        ngc_load
        NGC_HOSTNAME="$1"
        NGC_CERT="${2}/web.crt" NGC_KEY="${2}/web.key"
        cert_fits
    )
    mkdir -p "${certdir}/name"
    check "certificate: one is made for a name" \
        test "$(ngc_self ngc.example.org selfsigned "${certdir}/name")" = 1
    check "certificate: it answers for that name" \
        openssl x509 -in "${certdir}/name/web.crt" -noout -checkhost ngc.example.org
    check "certificate: and not for another one" \
        not openssl x509 -in "${certdir}/name/web.crt" -noout -checkhost ngc.somebody.else
    check "certificate: its key is 0600" test "$(stat -c %a "${certdir}/name/web.key")" = 600
    check "certificate: the certificate itself is 0644" \
        test "$(stat -c %a "${certdir}/name/web.crt")" = 644
    # 397 days, because a browser refuses a longer one even when somebody
    # trusted it by hand.
    check "certificate: it holds for another 396 days" \
        openssl x509 -in "${certdir}/name/web.crt" -noout -checkend 34214400
    check "certificate: and not for 398" \
        not openssl x509 -in "${certdir}/name/web.crt" -noout -checkend 34387200
    check "certificate: it says the browser will warn" \
        grep -q 'self-signed' "${certdir}/name/out"
    # cert_fits is what makes a second run leave it alone.
    check "cert_fits: the one just made fits" ngc_fits ngc.example.org "${certdir}/name"
    check "cert_fits: a certificate for another name does not fit" \
        not ngc_fits ngc.somebody.else "${certdir}/name"
    check "certificate: a second run leaves it as it is" \
        test "$(ngc_self ngc.example.org selfsigned "${certdir}/name")" = 0
    check "cert_fits: without a key nothing fits" \
        not ngc_fits ngc.example.org "${certdir}/empty"
    # An IP address needs IP: in the SAN, where a name needs DNS:.
    mkdir -p "${certdir}/ip"
    check "certificate: one is made for an IP address" \
        test "$(ngc_self 192.168.1.10 selfsigned "${certdir}/ip")" = 1
    check "certificate: it answers for that address" \
        openssl x509 -in "${certdir}/ip/web.crt" -noout -checkip 192.168.1.10
    check "certificate: the SAN says IP and not DNS" \
        grep -q 'IP Address:192.168.1.10' \
            <(openssl x509 -in "${certdir}/ip/web.crt" -noout -text)
    # In letsencrypt mode the self-signed one is only what the server starts
    # with, so the warning about 397 days does not belong there.
    mkdir -p "${certdir}/le"
    ngc_self ngc.example.org letsencrypt "${certdir}/le" > /dev/null
    check "certificate: in Let's Encrypt mode it says nothing about 397 days" \
        not grep -q 'self-signed' "${certdir}/le/out"

    # import: the two files have to belong together. A pair that does not would
    # leave Apache refusing to start, and nobody would know why.
    ngc_imp() (
        ngc_load
        ngc_env
        NGC_CERT_MODE=import NGC_CERT_FILE="$1" NGC_KEY_FILE="$2"
        NGC_CERT="${certdir}/imp/web.crt" NGC_KEY="${certdir}/imp/web.key"
        ensure_cert_import 2>&1
    )
    mkdir -p "${certdir}/imp"
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -noenc \
        -days 30 -subj "/CN=ngc.example.org" -keyout "${certdir}/a.key" \
        -out "${certdir}/a.crt" > /dev/null 2>&1
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -noenc \
        -days 30 -subj "/CN=ngc.example.org" -keyout "${certdir}/b.key" \
        -out "${certdir}/b.crt" > /dev/null 2>&1
    check "import: a certificate and its own key are taken" \
        ngc_imp "${certdir}/a.crt" "${certdir}/a.key" > /dev/null
    check "import: the certificate arrives, 0644" \
        test "$(stat -c %a "${certdir}/imp/web.crt")" = 644
    check "import: the key arrives, 0600" \
        test "$(stat -c %a "${certdir}/imp/web.key")" = 600
    check "import: a key of another certificate is refused" \
        not ngc_imp "${certdir}/a.crt" "${certdir}/b.key" > /dev/null
    check "import: and it says the two do not belong together" \
        grep -q 'do not belong together' <(ngc_imp "${certdir}/a.crt" "${certdir}/b.key")
    printf 'not a certificate\n' > "${certdir}/junk.crt"
    check "import: something that is no certificate is refused" \
        not ngc_imp "${certdir}/junk.crt" "${certdir}/a.key" > /dev/null
    check "import: a key that is no key is refused" \
        not ngc_imp "${certdir}/a.crt" "${certdir}/junk.crt" > /dev/null
    # A key with a password is no help to Apache either: nobody is at the
    # keyboard when it starts.
    openssl pkcs8 -topk8 -in "${certdir}/a.key" -passout pass:secret \
        -out "${certdir}/pw.key" > /dev/null 2>&1
    check "import: a key with a password is refused" \
        not ngc_imp "${certdir}/a.crt" "${certdir}/pw.key" > /dev/null
    check "import: and it says such a key is of no use to Apache" \
        grep -q 'protected by a password' <(ngc_imp "${certdir}/a.crt" "${certdir}/pw.key")

    # ---------------------------------------------------------- pin_of_cert
    # This is what ngc-web checks every API by. A fingerprint computed out of
    # nothing must never come back with 0 - it would be the same for every
    # certificate that cannot be read.
    ngc_pinof() (
        ngc_load
        pin_of_cert "$1"
    )
    pin="$(ngc_pinof "${certdir}/a.crt")"
    check "pin: 43 characters of base64url" ngc_pin "$pin"
    check "pin: the same certificate gives the same one" \
        test "$(ngc_pinof "${certdir}/a.crt")" = "$pin"
    check "pin: another certificate gives another one" \
        test "$(ngc_pinof "${certdir}/b.crt")" != "$pin"
    : > "${certdir}/empty.crt"
    check "pin: an empty file gives none" not ngc_pinof "${certdir}/empty.crt"
    check "pin: junk gives none" not ngc_pinof "${certdir}/junk.crt"
    check "pin: a file that is not there gives none" not ngc_pinof "${certdir}/no-such.crt"
    # The SHA-256 of nothing, which is what a failed pipeline would otherwise
    # hand back. It may never be a fingerprint.
    check "pin: never the SHA-256 of nothing" \
        not grep -qx '47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU' \
            <(ngc_pinof "${certdir}/empty.crt"; ngc_pinof "${certdir}/junk.crt")
else
    check "NOT MEASURED: openssl is here, so the certificates really were made" false
fi

# ------------------------------------------------------------------- uninstall
# The rule of the contract: uninstall asks what happens to the data, and kept
# data stays under /var/lib/ngc/ so a new installation finds it again. The
# harder half is what it must NOT touch - on a server with several roles
# api.json and controller.json lie in the same folder and belong to other
# parts.
ngc_uninstall() (
    ngc_load
    ngc_env
    # The two guards are measured where they belong (need_root is an EUID
    # test); here they would only stop the suite, which does not run as root.
    need_root() { :; }
    need_debian() { :; }
    base="$1"
    NGC_PURGE="$2"
    NGC_ETC="${base}/etc/ngc"
    NGC_TLS="${base}/etc/ngc/tls"
    NGC_WEB_JSON="${base}/etc/ngc/web.json"
    NGC_BALANCER="${base}/etc/ngc/apache-apis.conf"
    NGC_TRUST="${base}/etc/ngc/tls/api-trust.pem"
    NGC_CERT="${base}/etc/ngc/tls/web.crt"
    NGC_KEY="${base}/etc/ngc/tls/web.key"
    NGC_ROOT="${base}/var/www/ngc"
    NGC_KEPT="${base}/var/lib/ngc/web"
    SITE_FILE="${base}/sites-available/ngc-web.conf"
    SITE_KEPT="${SITE_FILE}.before-ulh"
    MD_FILE="${base}/conf-available/ngc-md.conf"
    uninstall_ngc_web > /dev/null 2>&1
)
ngc_make_install() {
    local base="$1"
    rm -rf "$base"
    mkdir -p "${base}/etc/ngc/tls" "${base}/var/www/ngc/public" \
        "${base}/var/lib/ngc" "${base}/sites-available" "${base}/conf-available"
    printf '{}\n' > "${base}/etc/ngc/web.json"
    printf 'x\n' > "${base}/etc/ngc/apache-apis.conf"
    printf 'x\n' > "${base}/etc/ngc/tls/api-trust.pem"
    printf 'x\n' > "${base}/etc/ngc/tls/web.crt"
    printf 'x\n' > "${base}/etc/ngc/tls/web.key"
    # Two files of OTHER parts of NGC on the same server.
    printf '{}\n' > "${base}/etc/ngc/api.json"
    printf '{}\n' > "${base}/etc/ngc/controller.json"
    printf '7\n' > "${base}/var/lib/ngc/release.seq"
    printf '<?php\n' > "${base}/var/www/ngc/public/index.php"
    printf '# hand written\n' > "${base}/sites-available/ngc-web.conf.before-ulh"
}
keepbase="${ngcdir}/un-keep"
ngc_make_install "$keepbase"
ngc_uninstall "$keepbase" no
check "uninstall: the web root is gone" not test -e "${keepbase}/var/www/ngc"
check "uninstall: the balancer is gone" not test -e "${keepbase}/etc/ngc/apache-apis.conf"
check "uninstall (keep): web.json stays where it was" test -f "${keepbase}/etc/ngc/web.json"
check "uninstall (keep): and a copy lies under /var/lib/ngc" \
    test -f "${keepbase}/var/lib/ngc/web/web.json"
check "uninstall (keep): the certificate is kept too" \
    test -f "${keepbase}/var/lib/ngc/web/web.crt"
check "uninstall (keep): what it keeps is 0700, not for everybody to read" \
    test "$(stat -c %a "${keepbase}/var/lib/ngc/web")" = 700
check "uninstall: api.json of the API part is not touched" \
    test -f "${keepbase}/etc/ngc/api.json"
check "uninstall: controller.json is not touched either" \
    test -f "${keepbase}/etc/ngc/controller.json"
check "uninstall: release.seq counts for every part and stays" \
    test -f "${keepbase}/var/lib/ngc/release.seq"
check "uninstall: a virtual host somebody wrote is never deleted" \
    test -f "${keepbase}/sites-available/ngc-web.conf.before-ulh"

purgebase="${ngcdir}/un-purge"
ngc_make_install "$purgebase"
ngc_uninstall "$purgebase" yes
check "uninstall (purge): web.json is gone" not test -e "${purgebase}/etc/ngc/web.json"
check "uninstall (purge): the certificate is gone" \
    not test -e "${purgebase}/etc/ngc/tls/web.crt"
check "uninstall (purge): its key is gone" \
    not test -e "${purgebase}/etc/ngc/tls/web.key"
check "uninstall (purge): api-trust.pem is gone" \
    not test -e "${purgebase}/etc/ngc/tls/api-trust.pem"
check "uninstall (purge): nothing is kept under /var/lib/ngc either" \
    not test -e "${purgebase}/var/lib/ngc/web"
# purge deletes the files of THIS script and no others. That is the whole
# difference between an uninstall and an accident.
check "uninstall (purge): api.json of the API part survives" \
    test -f "${purgebase}/etc/ngc/api.json"
check "uninstall (purge): controller.json survives" \
    test -f "${purgebase}/etc/ngc/controller.json"
check "uninstall (purge): release.seq survives" \
    test -f "${purgebase}/var/lib/ngc/release.seq"
check "uninstall (purge): the folder /etc/ngc itself is still there" \
    test -d "${purgebase}/etc/ngc"
check "uninstall (purge): the virtual host somebody wrote is still theirs" \
    test -f "${purgebase}/sites-available/ngc-web.conf.before-ulh"

# ------------------------------------------- the catalog entry, in five languages
# lang.test.sh measures this for the whole catalog; named here as well, so a
# missing translation of THIS script says which script it is.
ngccat="${ULH}/apps/cli/assets/catalog.yaml"
check "catalog: ngc-web is in it" \
    test "$("$YQ" '.scripts | has("ngc-web")' "$ngccat")" = true
check "catalog: it names ngc-web.sh" \
    test "$("$YQ" '.scripts."ngc-web".file' "$ngccat")" = ngc-web.sh
check "catalog: its description in all five languages" \
    test "$("$YQ" '[.scripts."ngc-web" | keys | .[] | select(test("^description"))] | length' \
        "$ngccat")" = 5
check "catalog: it has install, configure and uninstall" \
    test "$("$YQ" '[.scripts."ngc-web".actions[].name] | join(" ")' "$ngccat")" \
        = "install configure uninstall"
# The six answers of the contract, in the order the script's comment names
# them - ulh joins them with commas in exactly this order, so the order is part
# of the contract and not a detail of the file.
check "catalog: install asks the six answers of the contract, in that order" \
    test "$("$YQ" '[.scripts."ngc-web".actions[] | select(.name == "install") |
        .prompts[].variable] | join(" ")' "$ngccat")" \
        = "NGC_HOSTNAME NGC_CERT_MODE NGC_CERT_FILE NGC_KEY_FILE NGC_APIS NGC_API_PINS"
check "catalog: every question of ngc-web in all five languages" \
    test "$("$YQ" '[.scripts."ngc-web".actions[].prompts[] |
        [keys | .[] | select(test("^question"))] | length] | min' "$ngccat")" = 5
check "catalog: every action of ngc-web in all five languages" \
    test "$("$YQ" '[.scripts."ngc-web".actions[] |
        [keys | .[] | select(test("^description"))] | length] | min' "$ngccat")" = 5

# ======================================================= WHAT IS NOT MEASURED
# Every case below needs a tool this machine does not have. It is RED, not
# skipped: a case that steps over a missing tool is the worst kind of green.
if command -v jq > /dev/null 2>&1; then
    jqdir="${ngcdir}/jq"
    mkdir -p "$jqdir"
    ngc_rel_file() (
        ngc_load
        printf '%s' "$1" > "$WORK/payload.json"
        release_file
    )
    printf '{"seq":1,"files":[{"part":"ngc-web","arch":"all","url":"https://x/ngc-web.tar","sha256":"a","size":1}]}' \
        > "${jqdir}/p.json"
    check "release_file: the name of the one entry for ngc-web all" \
        test "$(ngc_rel_file "$(cat "${jqdir}/p.json")")" = ngc-web.tar
    check "release_file: a payload without an entry for ngc-web gives none" \
        not ngc_rel_file '{"seq":1,"files":[{"part":"ngc-api","arch":"amd64","url":"https://x/a.tar"}]}'
    check "release_file: two entries for ngc-web all give none" \
        not ngc_rel_file '{"seq":1,"files":[{"part":"ngc-web","arch":"all","url":"https://x/a.tar"},{"part":"ngc-web","arch":"all","url":"https://x/b.tar"}]}'
    check "release_file: a url whose last part is a path gives none" \
        not ngc_rel_file '{"seq":1,"files":[{"part":"ngc-web","arch":"all","url":"https://x/../etc/passwd"}]}'
else
    check "NOT MEASURED: jq is here, so release_file of ngc-web really ran" false
    check "NOT MEASURED: jq is here, so release_payload really ran" false
    check "NOT MEASURED: jq is here, so verify_release really ran (its 31 cases live in the NGC repository)" false
    check "NOT MEASURED: jq is here, so the refusal of an older release (release.seq) really ran" false
fi
if command -v shellcheck > /dev/null 2>&1; then
    check "shellcheck has nothing to say about ngc-web.sh" \
        shellcheck -s bash -S warning "${ULH}/apps/cli/assets/scripts/ngc-web.sh"
    check "shellcheck has nothing to say about this test" \
        shellcheck -s bash -S warning -x "${ULH}/apps/cli/tests/ngc-web.test.sh"
else
    check "NOT MEASURED: shellcheck is here, so ngc-web.sh really was looked over" false
fi
# These four need a machine, not a tool, and no case here pretends otherwise:
# sync_api_trust and fetch_cert need an API answering TLS 1.3 on a port,
# ensure_php needs Debian's conf-available, apache_apply needs Apache, and
# ensure_packages needs dpkg. They are named in docs and measured on the
# server, not here.

unset -f ngc_env ngc_is_ipv4 ngc_port ngc_url ngc_pin ngc_import ngc_b64url \
    ngc_put ngc_dir ngc_unpack ngc_md ngc_mods ngc_download ngc_self ngc_fits \
    ngc_imp ngc_pinof ngc_uninstall ngc_make_install ngc_rel_file 2>/dev/null
unset ngcbin putdir tardir certdir keepbase purgebase ngccat jqdir long \
    many_u many_p args pin nc m i
unset -f ngc_load ngc_balancer ngc_webjson ngc_answers ngc_host ngc_site \
    ngc_asset_walls ngc_template_walls ngc_check_template ngc_keep_site walls_in_site
unset ngcdir API1 API2 PIN1 PIN2 good bad shell w ngcroot

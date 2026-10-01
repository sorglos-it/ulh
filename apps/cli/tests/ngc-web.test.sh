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
ngc_check_template() (
    ngc_load
    VHOST_TEMPLATE="$1"
    check_vhost_template 2>&1
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
# This is the hole that was here before: /assets/ used to be taken out of the
# rewrite, so a MISSING file there was answered by Apache with no header at all.
#
# The same four walls stand once more in the NGC repository, in
# apps/web/templates/apache-vhost.conf. Changes there belong here too - and
# check_vhost_template of the script says so on a server that has both.
ngc_site > "${ngcdir}/site.got"

# Four headers have to reach an answer below /assets/: three out of the assets
# block, Strict-Transport-Security out of the host, where it covers every answer.
walls_in_site() {
    sed -n "\#^    <Directory ${1}/public/assets>\$#,\#^    </Directory>\$#p" "${ngcdir}/site.got" |
        grep -E '^        Header always set '
    grep -E '^    Header always set ' "${ngcdir}/site.got"
}
ngcroot="$(grep -m1 '^NGC_ROOT=' "${ngcdir}/body.sh" | cut -d'"' -f2)"
walls_in_site "$ngcroot" |
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
    grep -q "^    <Directory ${ngcroot}>\$" "${ngcdir}/site.got"
check "and it is denied, not granted" \
    test "$(sed -n "\#^    <Directory ${ngcroot}>\$#,\#^    </Directory>\$#p" "${ngcdir}/site.got" |
        grep -c '^        Require all denied$')" = 1

# -------------------------------------------- the second version, and its drift
# The NGC repository ships the same four walls as a template of its own. A
# release unpacks it beside the interface - whether it really carries the file is
# not settled, so the script never reads its virtual host from there. It does
# compare, and says so when the two have drifted apart.
cat > "${ngcdir}/tpl.conf" <<'EOF'
    <Directory "/var/www/ngc/public/assets">
        Header always set X-Content-Type-Options "nosniff"
        Header always set Cross-Origin-Resource-Policy "same-origin"
        Header always set Content-Security-Policy "default-src 'none'; script-src 'self'"
        Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains"
    </Directory>
EOF
ngc_template_walls "${ngcdir}/tpl.conf" > "${ngcdir}/walls.tpl"
check "the walls of the NGC template are read as the same four" \
    cmp -s "${ngcdir}/walls.list" "${ngcdir}/walls.tpl"
check "and the same template is called the same" \
    grep -q 'the same' <(ngc_check_template "${ngcdir}/tpl.conf")

grep -v 'Cross-Origin-Resource-Policy' "${ngcdir}/tpl.conf" > "${ngcdir}/tpl-short.conf"
check "a template with one wall fewer is named as different" \
    grep -q 'other protective settings' <(ngc_check_template "${ngcdir}/tpl-short.conf")
# A line the reader does not understand must not become a silent match: it would
# make a green run out of an installation with a hole.
printf 'Header always set X-Content-Type-Options nosniff\n' > "${ngcdir}/tpl-odd.conf"
check "a Header line it cannot read ends template_walls with 1" \
    not ngc_template_walls "${ngcdir}/tpl-odd.conf"
check "and check_vhost_template says so instead of calling it the same" \
    grep -q 'could not be read line by line' <(ngc_check_template "${ngcdir}/tpl-odd.conf")
# No file at all is the normal case today, and it may say nothing.
check "no template on the server means no message" \
    test -z "$(ngc_check_template "${ngcdir}/nothing-here.conf")"

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

unset -f ngc_load ngc_balancer ngc_webjson ngc_answers ngc_host ngc_site \
    ngc_asset_walls ngc_template_walls ngc_check_template ngc_keep_site walls_in_site
unset ngcdir API1 API2 PIN1 PIN2 good bad shell w ngcroot

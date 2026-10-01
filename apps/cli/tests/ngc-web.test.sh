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

unset -f ngc_load ngc_balancer ngc_webjson ngc_answers ngc_host
unset ngcdir API1 API2 PIN1 PIN2 good bad shell

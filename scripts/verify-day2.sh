#!/usr/bin/env bash
# Day 2 verification: NGINX secure reverse proxy lab
# Usage: bash scripts/verify-day2.sh   (backends on 8081/8082 must be running)
S=https; P=http
A=app1.lab.test; B=app2.lab.test
pass=0; fail=0

check() {  # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS  $1 ($3)"; pass=$((pass+1))
  else echo "FAIL  $1 (expected $2, got $3)"; fail=$((fail+1)); fi
}
code() { curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$@"; }

echo "== Day 2 verify: $(date -Is) =="

# Service and exposure
check "nginx service active" active "$(systemctl is-active nginx)"
public=$(ss -tlnH | awk '$4 ~ /:(80|443)$/ && $4 !~ /^127.0.0.1:/ && $4 !~ /^.::1.:/' | wc -l)
check "80/443 bound to loopback only" 0 "$public"

# Routing, redirect, catch-all
check "HTTP redirects to HTTPS" 301 "$(code "$P://$A/")"
check "app1 over HTTPS" 200 "$(code "$S://$A/")"
check "app2 over HTTPS" 200 "$(code "$S://$B/")"
check "unknown Host on 80 dropped" 000 "$(code -H 'Host: evil.test' "$P://127.0.0.1/")"
check "unknown SNI on 443 rejected" 000 "$(code -k --resolve evil.test:443:127.0.0.1 "$S://evil.test/")"

# TLS
check "TLS 1.2 accepted" 200 "$(code --tlsv1.2 --tls-max 1.2 "$S://$A/")"
check "TLS 1.1 refused" 000 "$(code --tls-max 1.1 "$S://$A/")"
check "HTTP/2 negotiated" 2 "$(curl -s -o /dev/null -w '%{http_version}' "$S://$A/")"

# Headers
hdrs=$(curl -s -D - -o /dev/null "$S://$A/")
check "server header hides version" "server: nginx" "$(echo "$hdrs" | grep -i '^server:' | tr -d '[:cntrl:]')"
for h in strict-transport-security x-content-type-options x-frame-options referrer-policy permissions-policy content-security-policy; do
  check "header $h" 1 "$(echo "$hdrs" | grep -ci "^$h:")"
done

# Access control
check "/admin without password" 401 "$(code "$S://$B/admin/")"
check "/admin from untrusted IP" 403 "$(code -u labadmin:x --interface 127.0.0.2 "$S://$B/admin/")"

# Rate limiting
sleep 2
n429=$(seq 60 | xargs -P 10 -I{} curl -s -o /dev/null -w "%{http_code} " "$S://$A/" | grep -o 429 | wc -l)
[ "$n429" -gt 0 ] && r=yes || r=no
check "flood gets 429s ($n429 of 60)" yes "$r"
sleep 3
check "recovers after flood" 200 "$(code "$S://$A/")"

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]

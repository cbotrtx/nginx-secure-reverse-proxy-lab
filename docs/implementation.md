# Implementation

Environment: Ubuntu 26.04, NGINX 1.28.3, OpenSSL 3.5.5, Python 3.14. Every change was backed up first, checked with `sudo nginx -t` and applied with `sudo systemctl reload nginx`.

## 1. Baseline (D2-01)
Backed up `/etc/nginx` to a tarball. Recorded listening ports, enabled sites and `/etc/hosts`. NGINX was already on loopback only from Project 1.

## 2. Backends (D2-02)
Started `python3 backends/app.py app1 8081 &` and `python3 backends/app.py app2 8082 &`. Each returns JSON describing the request it received.

## 3. HTTP reverse proxy (D2-03)
Added `app1.lab.test` and `app2.lab.test` to `/etc/hosts`. Created upstreams `app1_backend` and `app2_backend`, one server block per hostname, and the shared `proxy-headers.conf` snippet. Verified each hostname reached its own backend with the forwarded headers.

## 4. Private CA and certificate (D2-04)
In `~/lab-ca` (mode 700):
- CA: EC P-256, 730 days: `openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -noenc -keyout lab-ca.key -out lab-ca.crt -days 730 -sha256 -subj ...`
- Leaf: EC P-256 key and CSR, signed for 397 days with `server.ext` (SAN for both hosts, serverAuth): `openssl x509 -req -in lab.test.csr -CA lab-ca.crt -CAkey lab-ca.key -CAcreateserial -out lab.test.crt -days 397 -sha256 -extfile server.ext`
- Installed the cert and key in `/etc/nginx/ssl/` (key mode 600) and added the CA to the system trust store.

## 5. HTTPS (D2-05)
`tls-lab.conf`: TLSv1.2 and TLSv1.3, ciphers ECDHE-ECDSA-AES128-GCM-SHA256, ECDHE-ECDSA-AES256-GCM-SHA384 and ECDHE-ECDSA-CHACHA20-POLY1305, shared session cache 10m, timeout 1d, tickets off. Port 80 returns 301 to HTTPS. Port 443 has `http2 on`.

## 6. Catch-all (D2-06)
Removed the `default` site. Added `00-catch-all`: a port 80 default_server with `return 444` and a port 443 default_server with `ssl_reject_handshake on`.

## 7. Security headers (D2-07)
Changed `server_tokens build;` to `off` in `nginx.conf` line 22. Added `security-headers.conf` (HSTS 1 year, nosniff, DENY, strict-origin-when-cross-origin, Permissions-Policy, CSP `default-src 'none'; frame-ancestors 'none'`, all with `always`) and `proxy_hide_header X-Powered-By`. Included it in both HTTPS servers.

## 8. Rate limiting (D2-08)
`conf.d/rate-limit.conf`: `limit_req_zone` (10 r/s) and `limit_conn_zone` keyed on `$binary_remote_addr`, status 429. Both HTTPS servers: `limit_req zone=lab_req burst=20 nodelay` and `limit_conn lab_conn 20`.

## 9. Access control (D2-09)
Created `/etc/nginx/.htpasswd-lab` with `openssl passwd -6` (root:www-data, 640). `admin-acl.conf` defines `/admin/` with `satisfy all`, allow 127.0.0.1 and ::1, deny all, `auth_basic`, and a proxy to `app2_backend`. Included in the app2 HTTPS server only.

## 10. Logging (D2-10)
`conf.d/log-format.conf` defines `lab_security`: client, user, ISO time, host, request, status, bytes, request time, upstream address, status and time, TLS protocol and cipher, user agent. Both HTTPS servers log to `/var/log/nginx/lab-access.log` (rotated by Ubuntu's logrotate).

## 11. Verification (D2-11, D2-12)
`scripts/verify-day2.sh` runs 21 checks: 21/21 pass, and 21/21 after a reboot.

## Rollback
Each step has a backup under `~/backups/`. The full rollback is to restore the `/etc/nginx` tarball from step 1, remove the lab hosts from `/etc/hosts`, remove the lab CA from the trust store (`sudo update-ca-certificates --fresh` after deleting it), and reload NGINX.

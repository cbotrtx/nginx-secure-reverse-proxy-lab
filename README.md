# NGINX Secure Reverse Proxy Lab

A hardened NGINX reverse proxy in front of two backend apps, built and tested on Ubuntu 26.04. It covers TLS from a private CA, a default-deny catch-all, security headers, rate limiting, layered access control and security-focused logging. All of it is checked by one script and verified after a reboot.

Project 2 of 5 in my security lab series. Project 1: ubuntu-linux-security-hardening.

## Problem

Apps are rarely exposed directly. A reverse proxy sits in front and becomes the security boundary. Out of the box, though, NGINX on Ubuntu:

- serves plain HTTP
- answers requests for **any** hostname or IP, so it leaks a default page to scanners
- advertises its exact version (`server: nginx/1.28.3 (Ubuntu)`)
- sends no browser security headers
- has no rate limiting and no access control

Goal: turn a default NGINX into a proxy that only answers known sites, over modern TLS, and that limits, restricts and logs abuse. Then prove every control with repeatable tests.

## Architecture

```
                 (loopback only: 127.0.0.1 / ::1)
  client --> NGINX :80   -- 301 --> HTTPS
             NGINX :443  -- SNI/Host routing
                |--- app1.lab.test --> app1 backend 127.0.0.1:8081
                |--- app2.lab.test --> app2 backend 127.0.0.1:8082
                |                      /admin/ = IP allowlist + password
                |--- anything else --> catch-all (444 / TLS handshake rejected)
```

- **Hostnames:** `app1.lab.test`, `app2.lab.test` in `/etc/hosts`. `.test` is reserved for testing (RFC 2606), unlike `.local`, which belongs to mDNS.
- **Backends:** `backends/app.py`, a small Python JSON echo app, bound to loopback only.
- **TLS:** a private lab CA (EC P-256) signs one leaf certificate with both hostnames as SANs.

## Security controls

| Control | Implementation | File |
|---|---|---|
| Loopback-only exposure | `listen 127.0.0.1` / `[::1]` only | `configs/nginx/reverse-proxy-lab` |
| HTTPS everywhere | port 80 returns 301 to HTTPS | `configs/nginx/reverse-proxy-lab` |
| Modern TLS | TLS 1.2/1.3 only, ECDHE-ECDSA AEAD ciphers, tickets off, HTTP/2 | `configs/nginx/tls-lab.conf` |
| Default deny | unknown Host gets 444, unknown/no SNI gets a rejected handshake | `configs/nginx/00-catch-all` |
| No version leak | `server_tokens off` | `configs/nginx/nginx.conf` |
| Security headers | HSTS (1 year), nosniff, X-Frame-Options DENY, Referrer-Policy, Permissions-Policy, CSP; `X-Powered-By` hidden | `configs/nginx/security-headers.conf` |
| Rate limiting | 10 req/s per IP, burst 20, max 20 connections, returns 429 | `configs/nginx/conf.d/rate-limit.conf` |
| Access control | `/admin/` needs a loopback IP **and** Basic Auth (`satisfy all`) | `configs/nginx/admin-acl.conf` |
| Proxy headers | Host, X-Real-IP, X-Forwarded-For, X-Forwarded-Proto | `configs/nginx/proxy-headers.conf` |
| Security logging | vhost, user, status, upstream, timings, TLS version and cipher | `configs/nginx/conf.d/log-format.conf` |

## Implementation

Every change was backed up first and checked with `nginx -t` before reload.

1. **Baseline (D2-01):** recorded the default state; NGINX was already loopback-only from Project 1.
2. **Backends (D2-02):** started two echo apps on 8081 and 8082 and tested them directly.
3. **HTTP reverse proxy (D2-03):** name-based virtual hosts plus a shared proxy-headers snippet, verified per-host routing and forwarded headers.
4. **Private CA (D2-04):** created a lab CA and a leaf certificate (397 days, SAN for both hosts), installed it in NGINX and trusted the CA system-wide. Private keys never leave the machine.
5. **HTTPS (D2-05):** TLS 1.2/1.3 snippet, HTTP-to-HTTPS redirect, HTTP/2.
6. **Catch-all (D2-06):** removed the default site and added default servers that drop unknown hosts and reject unknown SNI (fixes D2-F01).
7. **Headers (D2-07):** turned off version disclosure (fixes D2-F02) and added six security headers with `always`, so error pages get them too.
8. **Rate limiting (D2-08):** a leaky-bucket limit per client IP, with 429 instead of NGINX's default 503.
9. **Access control (D2-09):** IP allowlist plus a salted SHA-512 password (`openssl passwd -6`) on `/admin/`.
10. **Logging (D2-10):** a custom `lab_security` log format in `/var/log/nginx/lab-access.log`.
11. **Verification (D2-11):** `scripts/verify-day2.sh` runs 21 automated checks.
12. **Reboot test (D2-12):** all 21 checks pass after a cold boot.

## Testing

With both backends running:

```bash
python3 backends/app.py app1 8081 &
python3 backends/app.py app2 8082 &
./scripts/verify-day2.sh
```

The script checks service state, loopback-only binding, the redirect, routing, catch-all behaviour, TLS versions, HTTP/2, version hiding, all six headers, `/admin/` returning 401 and 403, a 60-request flood and recovery. It exits non-zero if anything fails.

An untrusted client is simulated with `curl --interface 127.0.0.2`. Every 127.x address is loopback, but NGINX treats it as a different client IP.

## Results

| Test | Before | After | Evidence |
|---|---|---|---|
| Unknown Host / bare IP on :80 | default page served | connection dropped (444) | D2-06 |
| Unknown or missing SNI on :443 | served a certificate | handshake rejected (alert 112) | D2-06 |
| Server header | `nginx/1.28.3 (Ubuntu)` | `nginx` | D2-07 |
| Security headers | 0 | 6 | D2-07 |
| TLS | none | TLSv1.3 TLS_AES_256_GCM_SHA384, TLSv1.2 ECDHE-ECDSA-AES256-GCM-SHA384, TLS 1.1 refused | D2-05, D2-11 |
| Flood of 60 requests | all served | 22 served, 38 got 429, recovered after 3 s | D2-08 |
| `/admin/` | open | no password 401, wrong 401, correct 200, untrusted IP 403 | D2-09 |
| Blocked requests reach backend | n/a | no: `up=-` in the log for 401 and 403 | D2-10 |
| Automated checks | n/a | 21/21 pass, and 21/21 after reboot | D2-11, D2-12 |

## Findings

| ID | Severity | Finding | Status |
|---|---|---|---|
| D2-F01 | Medium | NGINX answered any Host and any SNI with the default site and certificate, which helps scanners fingerprint the server | Fixed (catch-all) |
| D2-F02 | Low | Ubuntu 26.04 ships `server_tokens build;` enabled, disclosing the exact version and distro | Fixed (`server_tokens off`) |
| D2-O01 | Observation | A probe for `/wp-login.php` was forwarded and answered 200. The proxy controls who and how much, not what. This is a hardening gap, not a vulnerability, since the backend is a test app | Planned: WAF in Project 3 |

## Limitations

- **Lab only:** everything is bound to loopback, and nothing has been tested against real network traffic.
- **Private CA:** trusted on this machine only. Production would use a public CA (for example ACME) with OCSP stapling.
- **Backends** are test echo apps run as shell jobs, not systemd services, so they do not start on boot.
- **Basic Auth** is a single shared account. It is safe here only because it runs over TLS; production would use SSO or MFA.
- **Rate limits** are per IP. Users behind one NAT share a bucket, and a distributed attack spreads across many.
- **HSTS** has no `includeSubDomains` or `preload`, which is deliberate for a test domain.
- **No content inspection:** see D2-O01, addressed in Project 3.

## Repository layout

```
backends/        test backend app
configs/nginx/   all NGINX config (conf.d/ = http-level)
configs/tls/     public certs only (lab CA, leaf, SAN extension)
evidence/        logs/ and test-results/, D2-01 to D2-12
scripts/         verify-day2.sh
```

Not in the repo by design: private keys (`*.key`), the htpasswd file and backups. Regenerate them to reproduce the lab.

## License

MIT, see LICENSE.

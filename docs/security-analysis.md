# Security Analysis

## Threat model

| Threat | Control | Evidence | Residual risk |
|---|---|---|---|
| Eavesdropping or tampering | TLS 1.2/1.3, AEAD ciphers, HSTS, 301 to HTTPS | D2-05 | First visit over HTTP before HSTS is cached (no preload) |
| Downgrade to old TLS | TLS 1.0/1.1 disabled | D2-11 | None in scope |
| Scanner fingerprinting | catch-all 444 and SNI rejection, `server_tokens off` | D2-06, D2-07 | `server: nginx` still names the product |
| Clickjacking | X-Frame-Options DENY, CSP frame-ancestors none | D2-07 | Old browsers ignore CSP |
| MIME sniffing | X-Content-Type-Options nosniff | D2-07 | None in scope |
| Brute force or flooding | 10 req/s per IP, burst 20, 20 connections, 429 | D2-08 | Distributed attacks, shared NAT IPs |
| Unauthorised admin access | IP allowlist AND Basic Auth (`satisfy all`) | D2-09 | Single shared account, no MFA or lockout |
| Attacks hidden in traffic | `lab_security` log with status, user, upstream and TLS | D2-10 | Logs are local and not centralised yet (Project 4) |
| Malicious request content | none at this layer | D2-10 (`wp-login.php` probe returned 200) | Open: WAF planned for Project 3 |

## Findings

### D2-F01: answers any Host and SNI (Medium, fixed)
Before: requests with an unknown Host header, a bare IP or an unknown SNI got the default site and the lab certificate. Scanners use this to fingerprint servers and find hidden virtual hosts.
Fix: `00-catch-all` with `return 444` on port 80 and `ssl_reject_handshake on` on port 443.
Verified: D2-06 and D2-11 (the curl result 000 means no HTTP response at all).

### D2-F02: version disclosure (Low, fixed)
Before: Ubuntu 26.04 ships `server_tokens build;` enabled in `nginx.conf`, giving `server: nginx/1.28.3 (Ubuntu)`.
Fix: changed it to `server_tokens off;` in place, since a second directive in `conf.d` would be a duplicate and fail `nginx -t`.
Verified: D2-07.

### D2-O01: no content inspection (observation)
A request for `/wp-login.php`, a common attack probe, was forwarded and answered 200. This is a hardening gap and not a vulnerability: the backend is a test echo app with no login page. A reverse proxy controls who connects and how often, but not what the request contains. Content inspection is a WAF's job (Project 3).

## Design decisions

- **Headers at server level only:** `add_header` is not inherited into a location that has its own `add_header`, so no location sets headers.
- **`always` on headers:** error responses (401, 403, 429) are protected too.
- **429, not 503:** 503 suggests an outage, while 429 tells the client it is rate limited.
- **`.test` hostnames:** reserved for testing. `.local` belongs to mDNS and can resolve unpredictably.
- **Private CA instead of self-signed leaf:** mirrors real PKI (CA, SAN, extended key usage) and lets the system trust the CA once.
- **Session tickets off:** keeps forward secrecy strong without key rotation tooling.

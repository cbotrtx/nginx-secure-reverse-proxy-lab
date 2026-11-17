# Architecture

## Components

| Component | Listens on | Role |
|---|---|---|
| NGINX 1.28.3 | 127.0.0.1 and ::1, ports 80 and 443 | Reverse proxy, TLS termination, security boundary |
| app1 backend (`backends/app.py`) | 127.0.0.1:8081 | Test JSON echo app (upstream `app1_backend`) |
| app2 backend (`backends/app.py`) | 127.0.0.1:8082 | Test JSON echo app (upstream `app2_backend`), has `/admin/` |
| Lab CA | offline, private key outside the repo | Signs the leaf certificate |

## Request flow

1. The client resolves `app1.lab.test` or `app2.lab.test` to 127.0.0.1 through `/etc/hosts`.
2. Port 80 only answers known hosts, with a 301 to HTTPS. Unknown hosts get 444 (connection closed).
3. Port 443 picks a server block by SNI. Unknown or missing SNI gets a rejected handshake.
4. In the matching server block, in order: rate limit, then (for `/admin/`) IP allowlist and Basic Auth, then proxy to the upstream with forwarding headers.
5. The response goes back with security headers added and `X-Powered-By` removed, and the request is logged in `lab_security` format.

## Trust boundaries

- **Client to NGINX:** untrusted. All controls apply here.
- **NGINX to backend:** trusted, loopback only, plain HTTP. Backends are never reachable from outside the host.
- **Lab CA private key:** the most sensitive asset. Stored in `~/lab-ca` (mode 700) and never committed.

## Config map

| Context | File | Purpose |
|---|---|---|
| http | `conf.d/rate-limit.conf` | rate and connection zones, 429 status |
| http | `conf.d/log-format.conf` | `lab_security` log format |
| http | `nginx.conf` | `server_tokens off` |
| server | `00-catch-all` | default servers for 80 and 443 |
| server | `reverse-proxy-lab` | upstreams, redirect server, app1 and app2 HTTPS servers |
| snippet | `tls-lab.conf` | certificate, protocols, ciphers, session settings |
| snippet | `security-headers.conf` | six response headers, hide `X-Powered-By` |
| snippet | `proxy-headers.conf` | Host, X-Real-IP, X-Forwarded-For, X-Forwarded-Proto |
| snippet | `admin-acl.conf` | `/admin/` location on app2 |

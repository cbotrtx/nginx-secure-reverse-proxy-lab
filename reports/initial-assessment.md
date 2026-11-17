# Initial Assessment (2026-11-17)

Scope: NGINX 1.28.3 on Ubuntu 26.04 as installed, after Project 1 hardening. Evidence: D2-01, D2-07 (before).

## State

| Area | Observed | Risk |
|---|---|---|
| Exposure | Bound to 127.0.0.1 and ::1 on port 80 only (from Project 1) | Low |
| Sites | Ubuntu `default` site enabled | Medium |
| Encryption | Plain HTTP only, no TLS | High in any real deployment |
| Unknown Host or IP | Answered with the default page | Medium (D2-F01) |
| Server header | `nginx/1.28.3 (Ubuntu)` (`server_tokens build;` by default) | Low (D2-F02) |
| Security headers | None | Medium |
| Rate limiting | None | Medium |
| Admin access control | None | High if an admin path exists |
| Logging | Default combined format, with no vhost, upstream or TLS fields | Low |

## Priorities

1. Add TLS and redirect HTTP to HTTPS.
2. Stop answering unknown hosts and SNI.
3. Remove version disclosure and add security headers.
4. Add rate limiting and admin access control.
5. Improve logs for later monitoring.

# Final Assessment (2026-11-17)

Scope: the same host after Project 2. Evidence: D2-05 to D2-12.

## Result

`scripts/verify-day2.sh`: 21/21 checks pass, and 21/21 after a reboot (D2-11, D2-12).

| Area | Before | After |
|---|---|---|
| Encryption | HTTP only | TLS 1.2/1.3, AEAD ciphers, HTTP/2, HSTS, 301 redirect |
| Unknown Host or SNI | default page | 444 and handshake rejected |
| Server header | `nginx/1.28.3 (Ubuntu)` | `nginx` |
| Security headers | 0 | 6 |
| Flood of 60 requests | all served | 22 served, 38 got 429, recovered in 3 s |
| `/admin/` | no control | 401 without or with a wrong password, 403 from an untrusted IP |
| Logging | default | `lab_security` format; blocked requests show `up=-` |

## Findings status

| ID | Severity | Status |
|---|---|---|
| D2-F01 Answers any Host and SNI | Medium | Fixed and verified |
| D2-F02 Version disclosure | Low | Fixed and verified |
| D2-O01 No content inspection | Observation | Open, planned for Project 3 (WAF) |

## Residual risks

Private CA trusted on this host only. Single shared Basic Auth account with no MFA or lockout. Per-IP rate limits. Logs are not centralised. Backends are not systemd services. See the README's Limitations section.

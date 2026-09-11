# Security considerations

BelTu-Agent intentionally keeps security-sensitive behaviors constrained:

- No `eval`.
- No stealth or evasion features.
- No credential harvesting.
- No external result-upload service.
- No hardcoded secrets or API keys.
- Scope is enforced on active stages when `--scope` is supplied.
- Rate and concurrency defaults are conservative.
- Commix is bounded by a configurable sample size and per-target timeout.

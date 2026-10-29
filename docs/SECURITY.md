# Security considerations

BelTu-Agent intentionally keeps security-sensitive behaviors constrained:

- No `eval`.
- No stealth or evasion features.
- No credential harvesting.
- No external result-upload service.
- No hardcoded secrets or API keys.
- A built-in hostname boundary limits active stages to the selected target and its DNS subdomains; external URLs from providers are discarded.
- Rate and concurrency defaults are conservative.
- Commix is bounded by a configurable sample size and per-target timeout.

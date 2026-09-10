# BelTu-Agent

A Bash CLI reconnaissance and vulnerability-scanning orchestrator for
**authorized** bug bounty and penetration testing engagements. It wraps
well-known open-source recon/scanning tools into one pipeline with strict
input sanitization, an automatic dependency installer, and a
Markdown/PDF executive report generator.

## ⚠️ Authorized Use Only

This tool is intended **exclusively** for security testing against assets
you own or have explicit written permission to test (bug bounty programs,
authorized penetration tests, your own labs). Running active scans or
crawlers against systems you are not authorized to test may be illegal in
your jurisdiction. You are solely responsible for how you use this tool.

## Features

- **Strict input sanitization** — the target domain is validated against a
  hard domain-format allow-list before it ever touches a shell command,
  blocking command-injection metacharacters entirely.
- **Automated dependency installer** — checks for `subfinder`,
  `assetfinder`, `amass`, `httpx`, `katana`, `gau`, `waybackurls`,
  `hakrawler`, `nuclei`, `dalfox`, `kxss`, `commix`, `jq`, `pandoc`, and
  `weasyprint`, and offers to install anything missing via `go install`,
  your system package manager, or `pip`.
- **Modular flags**:
  - `-d` — deep subdomain enumeration + active host probing
  - `-a` — URL crawling + parameter mining
  - `-v` — vulnerability scanning suite (nuclei, dalfox, kxss, commix)
  - `-f` — full pipeline (`-d` + `-a` + `-v`) with a compiled Markdown +
    PDF executive report
- **Clean output structure** — everything lands in a timestamped
  `recon_<target>_<timestamp>/` folder (raw logs, JSON, final report).

## Requirements

- Bash 4+ on Linux (tested against Debian/Ubuntu-style `apt` systems;
  `pacman`/`dnf`/`brew` are also detected for dependency installation).
- Go toolchain (auto-installed if missing) for the Go-based recon tools.
- `sudo` privileges for system package installation.

## Installation

```bash
git clone https://github.com/abdulrhmsnadel/BelTu-Agent.git
cd BelTu-Agent
chmod +x BelTu-Agent.sh
```

## Usage

```bash
./BelTu-Agent.sh -t <target-domain> [MODE]
```

| Flag | Description |
|---|---|
| `-t <domain>` | Target domain (required), e.g. `-t example.com` |
| `-d` | Deep subdomain enumeration & active host probing |
| `-a` | URL crawling & parameter mining |
| `-v` | Vulnerability scanning suite |
| `-f` | Full pipeline + Markdown/PDF report |
| `-h` | Show help |

### Examples

```bash
# Quick subdomain sweep
./BelTu-Agent.sh -t example.com -d

# Full pipeline with a compiled PDF report
./BelTu-Agent.sh -t example.com -f
```

On first run, if any dependency is missing, the script will prompt to
install it automatically. This can take a while the first time (Go tools
are compiled from source via `go install`).

## Output Structure

```
recon_example.com_20260910_142233/
├── subdomains/
│   ├── all_subdomains.txt
│   ├── live_hosts.txt
│   └── httpx_results.json
├── urls/
│   ├── all_urls.txt
│   └── urls_with_params.txt
├── vulnerabilities/
│   ├── nuclei_results.jsonl
│   ├── kxss_results.txt
│   ├── dalfox_results.txt
│   └── commix_results.txt
├── report.md
└── report.pdf
```

## Disclaimer

All findings produced by this tool are **automated and unverified** — they
require manual review before being submitted to any bug bounty program or
treated as confirmed vulnerabilities. The author assumes no liability for
misuse of this tool.

## License

MIT — see `LICENSE`.

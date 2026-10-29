# BelTu-Agent 1.1.3

BelTu-Agent is a Bash-based command-line orchestrator for authorized reconnaissance, URL collection, vulnerability checks, and evidence reporting. The active implementation in this repository is `BelTu-Agent.sh`; this repository is not the separate Python/Flutter BELTU application.

## What it does

- **Discovery (`-d`)**: Subfinder, Assetfinder, Amass, then HTTPX for live-host verification.
- **URL collection (`-a`)**: Katana, gau, waybackurls, and hakrawler; URL normalization, de-duplication, and parameter extraction.
- **Vulnerability checks (`-v`)**: Nuclei, kxss, Dalfox, and a bounded Commix run over parameterized URLs.
- **Full pipeline (`-f`)**: discovery → URL collection → vulnerability checks → Markdown/HTML/PDF reporting.
- Persistent per-run metadata, tool stdout/stderr logs, stage status, and resume support.

Automated detections are candidates, not confirmed vulnerabilities. Manually verify findings and impact before reporting them.

## Built-in target boundary

The `-t` argument accepts a bare domain or subdomain. The built-in boundary accepts only that exact hostname and DNS subdomains ending in `.<target>`. URLs from historical providers and crawler output are filtered to that boundary; Katana also receives an explicit target regex, and active scanners receive target-domain hosts only. For example, a run against `example.com` may include `api.example.com`, but rejects `notexample.com` and `example.org`.

Use this tool only for a target and its subdomains that you are authorized to assess. The built-in boundary is a hostname boundary, not proof of ownership, and it does not replace checking the rules of a bug-bounty program.

## Requirements

- Bash 4+
- Git and a package manager supported by the installer (apt, pacman, dnf, or Homebrew)
- Go for Go-based scanner utilities
- Optional tools are installed on demand only when explicitly requested or confirmed in an interactive terminal

For active use, the selected stages need these tools:

| Mode | Required utilities |
|---|---|
| `-d` | `subfinder`, `assetfinder`, `amass`, `httpx` |
| `-a` | `katana`, `gau`, `waybackurls`, `hakrawler` |
| `-v` | `nuclei`, `kxss`, `dalfox`, `commix` |
| `-f` report | `jq`, `pandoc`, `weasyprint` plus the stage tools |

Per-tool request rate/concurrency controls are applied where supported.

## Install

Clone the repository and install the user-local launcher:

`git clone https://github.com/abdulrhmsnadel/beltu-agent.git`

`cd beltu-agent`

`chmod +x BelTu-Agent.sh tests/test_beltu.sh`

`make test`

`make install-local`

If `~/.local/bin` is not in your `PATH`, add `export PATH="$HOME/.local/bin:$PATH"` to your shell profile, reload it, and check `beltu --version`.

A system-wide launcher can be installed with `make install`; this may require `sudo`. It does not automatically install scanner dependencies.

## Usage

`beltu --help`

`beltu --version`

`beltu -t example.com -d --dry-run --no-install`

`beltu -t example.com -a --rate-limit 3 --threads 5`

`beltu -t example.com -v --rate-limit 3 --threads 5`

`beltu -t example.com -f --install`

`beltu --resume recon_example.com_20260911_010000 -f`

Modes: `-d` discovery, `-a` URL collection, `-v` vulnerability checks, `-f` full pipeline. Options include `--threads`, `--rate-limit`, `--timeout`, `--retries`, `--max-injection-targets`, `--config`, `--resume`, `--install`, `--no-install`, `--dry-run`, and `--verbose`.

The combinations `--dry-run --install` and `--install --no-install` are rejected. `--dry-run` validates options and prints the proposed stages without running scanner binaries or installing dependencies. Dependency installation uses the system package manager and may invoke `sudo`, so request it explicitly.

## Configuration

Copy `config/beltu.conf.example` and pass it with `--config FILE`. Supported keys are `THREADS`, `RATE_LIMIT`, `TIMEOUT`, `RETRIES`, `MAX_INJECTION_TARGETS`, `NO_INSTALL`, and `VERBOSE`. Command-line values take precedence over configuration values.

## Output layout

Each run creates a `recon_<target>_<timestamp>/` folder containing:

- `metadata/`: target, configuration, stage state, and machine-readable `run.json`.
- `subdomains/`: raw discovery results, target-domain subdomains, HTTPX JSONL, and live hosts.
- `urls/`: raw provider/crawler results, normalized URLs, parameterized URLs, endpoints, and parameter names.
- `vulnerabilities/`: scanner result files.
- `logs/tools/`: command, stdout, stderr, duration, and exit-code logs.
- `report.md`, `report.html`, and `report.pdf` when report dependencies are available.

Resume a run with `beltu --resume <run-directory> -f`; completed stages are skipped.

## Development checks

`bash -n BelTu-Agent.sh`

`shellcheck -x BelTu-Agent.sh tests/test_beltu.sh`

`make test`

The GitHub Actions workflows run Bash checks and the test suite on pushes and pull requests.

## Safety notes

BelTu-Agent does not guarantee complete coverage. Scanner output can contain false positives, false negatives, stale URLs, or tool errors. A zero-finding report is not proof that a target is secure. Use conservative rate limits and only assess authorized domains.

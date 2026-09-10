# BelTu-Agent

BelTu-Agent is a Bash CLI orchestrator for **authorized** reconnaissance and security testing. It combines common discovery, HTTP probing, crawling, historical URL collection, parameter mining, automated vulnerability checks, and structured reporting into a single resumable pipeline.

> **Authorized use only.** Run BelTu-Agent only against systems you own or are explicitly authorized to assess. Respect the program scope, rate limits, terms of service, and applicable law.

## Version

**1.1.0**

## Project overview

BelTu-Agent keeps the original wrapper/orchestrator idea instead of replacing it with a new framework. The main command remains:

```bash
beltu -t example.com -f
```

The script can also be executed directly during development:

```bash
./BelTu-Agent.sh -t example.com -d
```

## Features

- Deep subdomain enumeration: `subfinder`, `assetfinder`, `amass`
- Active host probing and metadata: ProjectDiscovery `httpx`
- URL crawling: `katana`, `hakrawler`
- Historical URL collection: `gau`, `waybackurls`
- URL normalization and deduplication
- Parameterized URL and unique parameter extraction
- Automated checks: `nuclei`, `kxss`, `dalfox`, bounded `commix`
- Module-specific dependency validation instead of a full-system dependency check
- Tool identity/version/basic-execution validation
- Interactive dependency installation with explicit `--install` override
- Scope allowlist via `--scope`
- Conservative default rate limiting and concurrency controls
- Structured per-tool logs and module state
- Resume support
- Markdown, HTML, and PDF reporting
- `run.json` machine-readable metadata
- Bash 4+ implementation with no `eval`

## Architecture

```text
Target validation
      |
      +--> Scope validation (when --scope is supplied)
      |
      +--> Dependency mapping + tool validation
      |
      +--> Discovery / -d
      |      subfinder + assetfinder + amass
      |      -> deduplicate
      |      -> scoped assets
      |      -> httpx
      |
      +--> Crawling / -a
      |      live hosts or target fallback
      |      -> katana + gau + waybackurls + hakrawler
      |      -> URL normalization
      |      -> parameter mining
      |
      +--> Vulnerability / -v
      |      live hosts -> nuclei
      |      parameterized URLs -> kxss + dalfox + bounded commix
      |
      +--> Reporting / -f
             executive summary + attack surface + findings summary
             + tool coverage + raw-evidence references + disclaimer
```

## Installation

### 1. Clone

```bash
git clone https://github.com/YOUR-USERNAME/BelTu-Agent.git
cd BelTu-Agent
chmod +x BelTu-Agent.sh
```

### 2. Make `beltu` available globally

For the current user:

```bash
mkdir -p ~/.local/bin
ln -sf "$(pwd)/BelTu-Agent.sh" ~/.local/bin/beltu
export PATH="$HOME/.local/bin:$PATH"
```

To persist that PATH on Bash:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

You can still use the direct script path during development.

### 3. Dependencies

BelTu-Agent installs only the dependencies required by the selected mode. Dependencies are grouped as:

**`-d`**

- `subfinder`
- `assetfinder`
- `amass`
- `httpx`

**`-a`**

- `katana`
- `gau`
- `waybackurls`
- `hakrawler`

**`-v`**

- `nuclei`
- `kxss`
- `dalfox`
- `commix`

**Full reporting**

- `jq`
- `pandoc`
- `weasyprint`

Run with `--install` to explicitly authorize dependency installation:

```bash
beltu -t example.com -f --install
```

Without `--install`, an interactive terminal may ask before installing missing dependencies. In non-interactive execution, unattended installation is refused unless `--install` is explicitly provided.

Go-installed tools use user-space Go binaries; current Dalfox v3 uses the modern Rust-based install path when a native package is unavailable. WeasyPrint prefers the OS package and otherwise uses an isolated Python virtual environment rather than modifying system Python globally.

## Scope safety

Use a scope file whenever a program gives you an explicit allowlist:

```text
example.com
*.example.com
api.example.com
```

Run:

```bash
beltu -t example.com -f --scope examples/scope.txt.example
```

A wildcard `*.example.com` covers subdomains only; list `example.com` separately if the apex is in scope.

BelTu-Agent retains raw discovery outputs, but only assets passing the scope filter are fed into active probing/crawling/vulnerability stages when `--scope` is supplied.

## CLI usage

### Deep discovery

```bash
beltu -t example.com -d
```

### Crawling and parameter mining

```bash
beltu -t example.com -a --scope scope.txt
```

### Vulnerability checks

```bash
beltu -t example.com -v --rate-limit 3 --threads 5
```

### Full pipeline

```bash
beltu -t example.com -f --scope scope.txt
```

### Install dependencies explicitly

```bash
beltu -t example.com -f --install
```

### Dry run

```bash
beltu -t example.com -f --dry-run --no-install
```

### Resume

```bash
beltu --resume recon_example.com_20260911_010000 -f
```

### Help and version

```bash
beltu --help
beltu --version
```

## Configuration

Copy the example configuration:

```bash
cp config/beltu.conf.example config/beltu.conf
```

Then use:

```bash
beltu -t example.com -f --config config/beltu.conf
```

Supported settings:

```text
THREADS=10
RATE_LIMIT=5
TIMEOUT=10
RETRIES=1
MAX_INJECTION_TARGETS=20
NO_INSTALL=0
VERBOSE=0
```

Command-line options take precedence over values loaded from the config file, regardless of argument order.

## Output structure

```text
recon_example.com_TIMESTAMP/
├── metadata/
│   ├── target.txt
│   ├── config.txt
│   ├── scope.txt
│   ├── state.tsv
│   └── run.json
│
├── subdomains/
│   ├── subfinder.txt
│   ├── assetfinder.txt
│   ├── amass.txt
│   ├── all_subdomains.txt
│   ├── scoped_subdomains.txt
│   ├── live_hosts.txt
│   └── httpx_results.jsonl
│
├── urls/
│   ├── katana.txt
│   ├── gau.txt
│   ├── waybackurls.txt
│   ├── hakrawler.txt
│   ├── all_urls.txt
│   ├── urls_with_params.txt
│   ├── unique_endpoints.txt
│   ├── parameterized_endpoints.txt
│   └── unique_parameters.txt
│
├── vulnerabilities/
│   ├── nuclei_results.jsonl
│   ├── kxss_results.txt
│   ├── dalfox_results.txt
│   └── commix_results.txt
│
├── logs/
│   └── tools/
│       ├── *_<tool>.log
│       ├── *_<tool>.stdout.log
│       └── *_<tool>.stderr.log
│
├── report.md
├── report.html
└── report.pdf
```

## Reports

The report separates:

- Executive summary
- Attack surface
- Severity counts from structured scanner output where available
- Scanner/module status
- Tool coverage
- Raw-evidence references
- Verification guidance
- Authorized-use disclaimer

A scanner error is not reported as zero findings. For example, a failed Nuclei stage is marked as failed/skipped with its stderr log referenced.

Automated results are explicitly labeled as requiring manual verification. BelTu-Agent does not assign made-up severities.

## Logging and state

Every tool invocation records:

- UTC start/end timestamps
- Tool name
- Quoted command representation
- Result or output path
- stderr path
- Duration
- Exit code

Module state is kept in `metadata/state.tsv`. A scoped run also stores a copy of the scope allowlist at `metadata/scope.txt` so resuming does not silently drop the original scope. Completed modules are skipped on resume; failed/partial stages can be rerun.

## Rate limiting and safety defaults

Defaults are deliberately conservative:

```text
threads: 10
rate-limit: 5 requests/sec
request timeout: 10 sec
retries: 1
commix sample: 20 parameterized URLs
```

The values are configurable, but increasing them does not override the target's program rules or rate limits.

## Screenshots

Place real screenshots in your GitHub repository after testing:

```text
docs/screenshots/
├── cli-dry-run.png
├── full-pipeline.png
└── report-overview.png
```

The repository does not claim screenshots that were not actually captured.

## Troubleshooting

### `httpx found but validation failed`

Make sure the executable is ProjectDiscovery `httpx`, not another tool/package named `httpx`. Check:

```bash
command -v httpx
httpx -version
```

### Go tools install but are not found

BelTu-Agent adds the user Go bin path for its own process. For future shells you can persist it:

```bash
echo 'export PATH="$HOME/go/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### PDF is missing

Check whether both `pandoc` and `weasyprint` are installed and review:

```text
logs/tools/report_pandoc.stderr.log
logs/tools/report_weasyprint.stderr.log
```

### A scanner shows `failed/skipped`

Open the corresponding `logs/tools/*stderr.log` and `*.log` files. BelTu-Agent intentionally keeps tool errors instead of hiding them behind `2>/dev/null`.

### Resume says state is missing

The resume target must be a BelTu-Agent output directory containing:

```text
metadata/target.txt
metadata/state.tsv
```

## Limitations

- The project is Bash-first and depends on external security tools; upstream CLI changes can require adapter updates.
- Historical URL providers can return stale or duplicate data.
- Automated scanner results are not proof of exploitability.
- Parameter mining is deliberately lightweight and does not replace manual application mapping.
- Scope matching is domain-based and intentionally does not interpret complex program-specific wildcard syntax beyond `*.example.com`.
- Commix is intentionally bounded and conservative.

## Roadmap

- Add fixture-based parser tests for more URL shapes
- Add optional CSV/SARIF summary exports without external services
- Add per-program header/rate-limit profiles stored locally
- Add more resilient adapter detection for upstream CLI changes

## License

MIT. See `LICENSE`.

## Legal disclaimer

You are solely responsible for ensuring that you have permission to test every target. This project is designed for authorized security assessments, bug bounty programs, labs, and environments where the operator has explicit authorization.

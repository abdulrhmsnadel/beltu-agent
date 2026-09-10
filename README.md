# BelTu-Agent

BelTu-Agent is a Bash CLI orchestrator for **authorized** reconnaissance and security testing. It combines discovery, HTTP probing, crawling, historical URL collection, parameter mining, automated vulnerability checks, state tracking, and structured reporting into a single resumable pipeline.

> **Authorized use only.** Run BelTu-Agent only against systems you own or are explicitly authorized to assess. Respect the target program scope, rate limits, terms of service, and applicable law.

## Version

**1.1.1**

## Project overview

BelTu-Agent preserves the original wrapper/orchestrator architecture instead of replacing it with a new framework.

The primary CLI command is:

```bash
beltu -t example.com -f
```

The script can also be executed directly during development:

```bash
./BelTu-Agent.sh -t example.com -d
```

The project is intentionally Bash-first and does not require any external AI service or API.

## Features

* Deep subdomain enumeration with `subfinder`, `assetfinder`, and `amass`
* Active host probing with ProjectDiscovery `httpx`
* URL crawling with `katana` and `hakrawler`
* Historical URL collection with `gau` and `waybackurls`
* URL normalization and deduplication
* Unique endpoint extraction
* Parameterized URL extraction
* Unique parameter extraction
* Automated checks with `nuclei`, `kxss`, `dalfox`, and bounded `commix`
* Module-specific dependency validation
* Tool identity and CLI compatibility validation
* Version detection for supported tools
* Interactive dependency installation
* Explicit dependency installation with `--install`
* Installation prevention with `--no-install`
* Real dry-run mode with no installation or scanning
* Scope allowlist enforcement with `--scope`
* Native crawler scope restrictions where supported
* Post-crawl scope filtering as an additional safety layer
* Conservative concurrency and per-tool rate controls
* Configurable timeouts and retries
* Bounded command-injection testing targets
* Structured per-tool logging
* Module state tracking
* Resume support
* Accumulated runtime tracking across resumed runs
* Machine-readable `run.json`
* Markdown, HTML, and PDF reports
* Clear distinction between scanner failure and zero findings
* Bash 4+ implementation
* No `eval`
* No external result-upload service
* No stealth, evasion, destructive, or credential-theft functionality

## Architecture

```text
Target validation
      |
      +--> Scope validation
      |      exact domains + supported wildcard entries
      |
      +--> Dependency mapping
      |      only dependencies required by selected mode(s)
      |
      +--> Tool validation
      |      executable + identity + CLI compatibility + version
      |
      +--> Discovery / -d
      |      subfinder
      |      assetfinder
      |      amass
      |          |
      |          +--> deduplication
      |          +--> scope filtering
      |          +--> httpx
      |
      +--> Crawling / -a
      |      live hosts from -d when available
      |      target fallback otherwise
      |          |
      |          +--> pre-crawl scope enforcement
      |          +--> katana native scope controls
      |          +--> katana
      |          +--> gau
      |          +--> waybackurls
      |          +--> hakrawler
      |          +--> post-crawl scope filtering
      |          +--> URL normalization
      |          +--> parameter mining
      |
      +--> Vulnerability / -v
      |      live hosts -> nuclei
      |      parameterized URLs -> kxss
      |      parameterized URLs -> dalfox
      |      bounded parameterized URLs -> commix
      |
      +--> State / Resume
      |      module status
      |      original start time
      |      accumulated runtime
      |
      +--> Reporting / -f
             executive summary
             attack surface
             findings summary
             scanner status
             tool coverage
             raw-evidence references
             verification guidance
             disclaimer
```

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/YOUR-USERNAME/BelTu-Agent.git
cd BelTu-Agent
chmod +x BelTu-Agent.sh
```

### 2. Install the `beltu` command

Recommended local installation:

```bash
make install-local
```

This installs a user-level launcher without requiring a system-wide installation.

You can then ensure the local binary directory is in your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

To persist it for future Bash sessions:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

You can always run the project directly during development:

```bash
./BelTu-Agent.sh -t example.com -d
```

### 3. Check the installation

```bash
beltu --version
```

Expected:

```text
BelTu-Agent v1.1.1
```

You can also verify the CLI:

```bash
beltu --help
```

## Dependencies

BelTu-Agent performs **module-specific dependency validation**. It does not require every supported security tool for every mode.

### `-d` — Discovery

```text
subfinder
assetfinder
amass
httpx
```

### `-a` — Crawling and parameter mining

```text
katana
gau
waybackurls
hakrawler
```

### `-v` — Vulnerability checks

```text
nuclei
kxss
dalfox
commix
```

### `-f` — Full pipeline and reporting

```text
subfinder
assetfinder
amass
httpx
katana
gau
waybackurls
hakrawler
nuclei
kxss
dalfox
commix
jq
pandoc
weasyprint
```

For example:

```bash
beltu -t example.com -d
```

does not require `dalfox`, `commix`, `pandoc`, or `weasyprint`.

## Dependency installation

BelTu-Agent does not silently install missing dependencies when explicit installation has not been requested.

Use:

```bash
beltu -t example.com -f --install
```

to explicitly allow dependency installation.

The installer supports common package managers where available:

```text
apt
pacman
dnf
brew
```

Go-based tools are installed into user-space Go binaries.

Where a Python fallback is required for WeasyPrint, BelTu-Agent uses an isolated virtual environment rather than modifying the system Python environment globally.

### Disable installation

Use:

```bash
beltu -t example.com -f --no-install
```

When `--no-install` is used, missing or invalid dependencies are reported and affected modules are skipped or marked unavailable.

### Installation conflicts

The following combination is rejected:

```bash
beltu -t example.com -f --install --no-install
```

Error:

```text
[x] --install and --no-install cannot be used together
```

## Dry run

`--dry-run` is a real planning mode.

Example:

```bash
beltu -t example.com -f --dry-run --no-install
```

Dry run:

* validates the target
* validates the scope when supplied
* validates configuration values
* calculates the selected execution plan
* shows which stages would run
* does not perform active scanning
* does not execute security tools
* does not install dependencies

The following combination is intentionally rejected:

```bash
beltu -t example.com -f --dry-run --install
```

Error:

```text
[x] --dry-run cannot be combined with --install
```

This guarantees that a dry run cannot unexpectedly modify the system through dependency installation.

## Scope safety

Use a scope file whenever a program provides an explicit asset allowlist.

Example:

```text
example.com
*.example.com
api.example.com
```

Run:

```bash
beltu -t example.com -f --scope scope.txt
```

A wildcard such as:

```text
*.example.com
```

covers subdomains only.

If the apex domain is also explicitly in scope, list it separately:

```text
example.com
*.example.com
```

### Scope enforcement

BelTu-Agent applies scope checks at multiple stages.

```text
scope validation
      ↓
in-scope discovery assets
      ↓
in-scope crawler input
      ↓
native crawler scope controls where supported
      ↓
post-crawl URL filtering
      ↓
in-scope vulnerability inputs
```

This is intentionally layered.

The crawler is not intended to freely follow unrelated external hosts and rely only on filtering the results afterward.

The scope file is copied into the run directory so that a resumed run retains the original allowlist:

```text
metadata/scope.txt
```

## Scope format

Currently supported entries are:

```text
example.com
api.example.com
*.example.com
```

Comments are supported:

```text
# Production scope
example.com
*.example.com
```

The parser is intentionally structured so future versions can add exclusion entries such as:

```text
!admin.example.com
```

without redesigning the scope engine.

## CLI usage

### Deep discovery

```bash
beltu -t example.com -d
```

Pipeline:

```text
subfinder
→ assetfinder
→ amass
→ deduplication
→ scope filtering
→ httpx
```

### Crawling and parameter mining

```bash
beltu -t example.com -a
```

With scope:

```bash
beltu -t example.com -a --scope scope.txt
```

Pipeline:

```text
live hosts from -d
        ↓
scope enforcement
        ↓
katana + gau + waybackurls + hakrawler
        ↓
URL normalization
        ↓
deduplication
        ↓
parameter extraction
```

### Vulnerability checks

```bash
beltu -t example.com -v
```

With conservative controls:

```bash
beltu -t example.com -v \
  --threads 5 \
  --rate-limit 3 \
  --timeout 10 \
  --retries 1
```

### Full pipeline

```bash
beltu -t example.com -f
```

With scope:

```bash
beltu -t example.com -f --scope scope.txt
```

Pipeline:

```text
Discovery
→ Live Hosts
→ Crawling
→ URL Processing
→ Parameters
→ Vulnerability Checks
→ Analysis
→ Reporting
```

### Explicit installation

```bash
beltu -t example.com -f --install
```

### No installation

```bash
beltu -t example.com -f --no-install
```

### Dry run

```bash
beltu -t example.com -f --dry-run --no-install
```

### Resume

```bash
beltu --resume recon_example.com_20260911_010000
```

You can also specify a stage selection when needed:

```bash
beltu --resume recon_example.com_20260911_010000 -f
```

When no explicit mode is supplied with `--resume`, BelTu-Agent uses the full pipeline and skips stages already marked `completed`.

### Help and version

```bash
beltu --help
beltu --version
```

## Command-line options

### Legacy-compatible options

```text
-t, --target DOMAIN
-d
-a
-v
-f
-h, --help
```

### Additional options

```text
--scope FILE
--config FILE
--resume DIR
--threads N
--rate-limit N
--timeout N
--retries N
--max-injection-targets N
--install
--no-install
--dry-run
--verbose
--version
```

## Numeric safety limits

BelTu-Agent validates numeric configuration values before running.

Current supported bounds:

```text
--threads                1..100
--rate-limit             1..1000
--timeout                1..300 seconds
--retries                0..5
--max-injection-targets  1..100
```

Examples of invalid input:

```bash
beltu -t example.com -d --threads 999999999
```

```bash
beltu -t example.com -d --timeout 0
```

```bash
beltu -t example.com -v --retries 999
```

These values are rejected before scanning begins.

## Rate limiting and concurrency

The controls are deliberately conservative by default:

```text
threads: 10
rate-limit: 5
timeout: 10
retries: 1
```

The description of `--rate-limit` is intentionally limited:

> **Per-tool request rate/concurrency controls where supported**

It is **not** a claim of a universal network-wide requests-per-second limiter.

Different security tools expose different concurrency and rate controls, so BelTu-Agent maps the configuration to individual tools where their CLI supports it.

Increasing these values never overrides the target program's own rules.

Always follow the scope and rate restrictions of the authorized engagement.

## Bounded command-injection testing

`commix` operates on a bounded sample of parameterized URLs.

Default:

```text
20 targets
```

Configure it with:

```bash
beltu -t example.com -v --max-injection-targets 10
```

The bound exists to prevent an accidental large-scale command-injection probe.

## Configuration

Copy the example file:

```bash
cp config/beltu.conf.example config/beltu.conf
```

Use it with:

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

CLI arguments take precedence over configuration values.

This precedence is maintained regardless of the argument order.

## Target validation

Targets are intentionally restricted to bare domains/subdomains.

Supported examples:

```text
example.com
api.example.com
test.api.example.com
```

The following are rejected:

```text
https://example.com
http://example.com
example.com/path
example.com:443
example .com
example.com;id
example.com|id
```

The validation rejects shell metacharacters and does not use `eval`.

Commands are passed to tools as Bash arrays rather than constructing executable command strings.

## URL processing

BelTu-Agent performs URL normalization and deduplication before parameter analysis.

For example:

```text
https://example.com/api/user?id=1
https://example.com/api/user?id=2
https://example.com/api/user?id=3
```

are preserved as distinct raw URLs while allowing the analysis layer to identify:

```text
Endpoint:
/api/user

Parameter:
id
```

Generated artifacts include:

```text
urls/all_urls.txt
urls/urls_with_params.txt
urls/unique_endpoints.txt
urls/parameterized_endpoints.txt
urls/unique_parameters.txt
```

The URL processor does not arbitrarily rewrite parameter values during normalization.

## Output structure

A typical run produces:

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

Raw outputs remain available for manual investigation.

## Logging

Each tool invocation records structured information including:

* UTC timestamp
* Tool name
* Command representation
* Input count
* Output path
* stderr path
* Start time
* End time
* Duration
* Exit code

Example:

```text
start_epoch=...
end_epoch=...
duration_seconds=...
exit_code=0
```

Tool stdout and stderr are stored separately where applicable.

BelTu-Agent intentionally does not hide tool errors behind blanket `2>/dev/null` redirection.

## State tracking

Module state is stored in:

```text
metadata/state.tsv
```

Supported module states include:

```text
not_run
running
completed
partial
failed
skipped
```

Example:

```text
deep_enum    completed
url_crawl    completed
vuln_scan    partial
report       not_run
```

A module is skipped during resume only when its state is `completed`.

Failed or partial stages can be rerun.

## Resume behavior

Resume is designed for interrupted or partially completed runs.

Example:

```bash
beltu --resume recon_example.com_20260911_010000
```

The run retains:

```text
original start time
resume time
accumulated duration
module state
original scope snapshot
```

This prevents the runtime in `run.json` from being reset to zero when a run is resumed.

Resume does not require rebuilding completed stages unnecessarily.

## `run.json`

Each run contains machine-readable metadata:

```text
metadata/run.json
```

Example structure:

```json
{
  "tool": "BelTu-Agent",
  "version": "1.1.1",
  "target": "example.com",
  "started_at": "2026-09-11T00:00:00Z",
  "finished_at": "2026-09-11T00:12:00Z",
  "mode": "full",
  "status": "completed",
  "dry_run": 0,
  "scope_file": "metadata/scope.txt",
  "output_directory": "recon_example.com_20260911_000000",
  "duration_seconds": 720,
  "modules": {
    "deep_enum": "completed",
    "url_crawl": "completed",
    "vuln_scan": "completed",
    "report": "completed"
  }
}
```

Runtime values shown above are examples only.

## Deep enumeration status

BelTu-Agent distinguishes between:

```text
completed
partial
failed
```

A target seed by itself does not count as a successful enumeration result.

For example, if:

```text
subfinder   failed
assetfinder failed
amass       failed
httpx       failed
```

the discovery stage is not reported as successful merely because the original target exists as a seed.

A stage can be marked `partial` when some meaningful processing succeeded while one or more tools failed.

## Vulnerability scanning status

Each scanner is tracked independently:

```text
nuclei
kxss
dalfox
commix
```

Possible states include:

```text
completed
failed
skipped
```

Scanner output is treated as automated detection and not automatically as confirmed vulnerability evidence.

## Zero findings versus scanner failure

The report explicitly distinguishes:

```text
0 findings
```

from:

```text
Scanner failed
```

and:

```text
Scanner skipped/unavailable
```

For example:

```text
Nuclei: Scanner failed.
Severity counts are not interpreted as zero.
```

A successful Nuclei scan with no detections may instead report:

```text
Critical: 0
High: 0
Medium: 0
Low: 0
Informational: 0
```

These are materially different outcomes.

## Reports

The reporting pipeline can generate:

```text
report.md
report.html
report.pdf
```

The report contains:

### Executive Summary

```text
Target
Assessment Date
Tool Version
Scan Mode
Overall Status
```

### Attack Surface

```text
Subdomains
Live Hosts
URLs
Parameterized URLs
Unique Endpoints
Unique Parameters
```

### Findings Summary

Severity counts are presented only when supported by structured scanner output.

BelTu-Agent does not invent or infer severity values.

### Scanner Results

Each scanner includes its status and raw-evidence reference.

### Tool Coverage

The report records:

```text
validated
missing
found, validation failed
not required
```

### Module Status

The report shows:

```text
Deep Enumeration
URL Crawling
Vulnerability Scanning
Reporting
```

### Raw Evidence

The report points to the raw outputs and logs rather than unnecessarily copying entire scanner output into the document.

### Verification Guidance

Automated detections should be manually reproduced and verified before being treated as confirmed findings.

## Automated detection disclaimer

BelTu-Agent is an orchestration and automation tool.

Automated results can contain:

```text
false positives
false negatives
stale historical data
scanner-specific errors
incomplete coverage
```

An automated detection is not automatically a confirmed security vulnerability.

Likewise:

```text
0 findings
```

does not prove that the target is secure.

## Security design

BelTu-Agent intentionally avoids:

```text
eval
command-string execution
credential theft
destructive operations
stealth/evasion
authorization bypass
external result uploads
hardcoded API keys
```

The target is validated before commands are constructed, and external commands are invoked using Bash arrays with explicit quoting.

## Screenshots

The repository does not claim screenshots that have not actually been captured.

Recommended GitHub screenshots:

```text
docs/screenshots/
├── cli-dry-run.png
├── dependency-validation.png
├── full-pipeline.png
└── report-overview.png
```

## Testing

Run the built-in test suite:

```bash
./tests/test_beltu.sh
```

Or:

```bash
make test
```

The test suite covers critical behavior including:

```text
Bash syntax
CLI compatibility
target validation
shell metacharacter rejection
module selection
dependency mapping
scope matching
scope filtering
crawler scope enforcement
dry-run behavior
install conflicts
numeric bounds
output handling
deep enumeration status classification
resume behavior
run metadata
```

When available, the test suite can also run ShellCheck validation.

### Basic manual tests

Syntax:

```bash
bash -n BelTu-Agent.sh
```

Version:

```bash
./BelTu-Agent.sh --version
```

Help:

```bash
./BelTu-Agent.sh --help
```

Dry run:

```bash
./BelTu-Agent.sh \
  -t example.com \
  -f \
  --dry-run \
  --no-install
```

Expected behavior:

```text
No scanning
No tool execution
No dependency installation
```

Invalid dry-run combination:

```bash
./BelTu-Agent.sh \
  -t example.com \
  -f \
  --dry-run \
  --install
```

Expected:

```text
[x] --dry-run cannot be combined with --install
```

Invalid installation combination:

```bash
./BelTu-Agent.sh \
  -t example.com \
  -f \
  --install \
  --no-install
```

Expected:

```text
[x] --install and --no-install cannot be used together
```

## Troubleshooting

### `httpx found but validation failed`

Make sure the executable is ProjectDiscovery `httpx`, not another executable named `httpx`.

Check:

```bash
command -v httpx
httpx -version
```

### A security tool is missing

Check the selected module.

For example:

```bash
beltu -t example.com -d --no-install
```

only requires the discovery dependencies.

Use:

```bash
beltu -t example.com -f --install
```

to explicitly allow installation of dependencies required by the full pipeline.

### Go tools are installed but not found

Check:

```bash
echo "$PATH"
echo "$HOME/go/bin"
```

You can persist the Go binary path:

```bash
echo 'export PATH="$HOME/go/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### PDF is missing

Check:

```text
logs/tools/report_pandoc.stderr.log
logs/tools/report_weasyprint.stderr.log
```

Also verify:

```bash
pandoc --version
weasyprint --version
```

### A scanner reports `failed`

Inspect:

```text
logs/tools/
```

especially the corresponding:

```text
*.stderr.log
*.log
```

BelTu-Agent intentionally preserves tool errors for troubleshooting.

### Resume fails

The resume directory must contain:

```text
metadata/target.txt
metadata/state.tsv
```

Example:

```bash
beltu --resume recon_example.com_20260911_010000
```

### Scope rejects the target

Confirm that the target or its parent scope is explicitly listed.

Example:

```text
example.com
*.example.com
```

Remember that:

```text
*.example.com
```

does not by itself include the apex:

```text
example.com
```

## Limitations

* BelTu-Agent depends on external security tools whose upstream CLI interfaces may change.
* Tool compatibility validation reduces silent failures but cannot guarantee long-term compatibility with every future release.
* Historical URL providers may return stale or duplicated data.
* Crawlers and scanners have different semantics for concurrency and rate controls.
* `--rate-limit` is not a universal network-wide rate limiter.
* Parameter mining is intentionally lightweight and does not replace manual application mapping.
* Scope syntax currently supports exact domains and `*.example.com`-style wildcards.
* Automated findings require manual verification.
* Commix is intentionally bounded.
* PDF generation depends on Pandoc/WeasyPrint availability.
* The tool does not guarantee complete security-test coverage.

## Roadmap

Possible future improvements include:

* Scope exclusions such as `!admin.example.com`
* More fixture-based URL parser tests
* Additional structured report formats such as CSV or SARIF
* Local per-program configuration profiles
* More resilient upstream CLI compatibility adapters
* Expanded reporting analytics
* Additional regression fixtures for uncommon URL forms

## License

MIT License. See [`LICENSE`](LICENSE).

## Legal disclaimer

You are solely responsible for ensuring that you have permission to test every target.

BelTu-Agent is intended for:

```text
authorized security assessments
bug bounty programs
security labs
training environments
systems you own
```

Do not use BelTu-Agent against systems without explicit authorization.

The existence of a technical capability in the project does not grant permission to use it against a target.

Always follow:

```text
program scope
rate limits
terms of service
applicable law
```

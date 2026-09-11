# BelTu-Agent

BelTu-Agent is a Bash CLI orchestrator for **authorized** reconnaissance and security testing. It keeps the existing wrapper/orchestrator architecture and combines discovery, HTTP probing, crawling, historical URL collection, parameter mining, automated checks, state tracking, and reporting in one resumable pipeline.

> **Authorized use only.** Run BelTu-Agent only against systems you own or are explicitly authorized to assess. Respect the program scope, rate limits, terms of service, and applicable law.

## Version

**1.1.2**

This release is a focused installability/runtime-entrypoint fix to the 1.1.x architecture. It does not replace the project with a new framework and does not remove the existing discovery, crawling, scanning, scope, state, logging, or reporting features.

## Project overview

The main CLI remains:

```bash
beltu -t example.com -f
```

The script is also directly executable during development:

```bash
./BelTu-Agent.sh -t example.com -d
```

## Features

- Deep subdomain enumeration: `subfinder`, `assetfinder`, `amass`
- Active host probing: ProjectDiscovery `httpx`
- URL crawling: `katana`, `hakrawler`
- Historical URL collection: `gau`, `waybackurls`
- URL normalization and deduplication
- Parameterized URL, endpoint, and unique-parameter extraction
- Automated checks: `nuclei`, `kxss`, `dalfox`, bounded `commix`
- Module-specific dependency mapping
- Tool identity, version, and CLI compatibility validation
- Explicit and interactive dependency installation
- Scope allowlist with pre-crawl filtering and Katana native scope restrictions
- Post-crawl/post-provider scope filtering as a defense-in-depth layer
- Per-tool request rate/concurrency controls where supported
- Bounded runtime options to avoid accidental extreme values
- Structured per-tool logs with stdout/stderr separation
- Resumable module state
- Accumulated duration across resume operations
- Markdown, HTML, and PDF reporting
- `run.json` machine-readable metadata
- Bash 4+ implementation
- No `eval`, stealth/evasion, credential theft, destructive actions, or external result-upload service

## Architecture

```text
Target validation
      |
      +--> Scope validation (when --scope is supplied)
      |
      +--> Module-specific dependency mapping + tool validation
      |
      +--> Discovery / -d
      |      subfinder + assetfinder + amass
      |      -> deduplicate
      |      -> scoped assets
      |      -> httpx
      |
      +--> Crawling / -a
      |      live in-scope hosts or target fallback
      |      -> Katana native scope controls when supported
      |      -> gau + waybackurls + hakrawler
      |      -> post-filtering
      |      -> URL normalization
      |      -> parameter mining
      |
      +--> Vulnerability / -v
      |      in-scope live hosts -> nuclei
      |      parameterized URLs -> kxss + dalfox + bounded commix
      |
      +--> Reporting / -f
             executive summary + attack surface + findings
             + module/tool coverage + evidence references
```

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/abdulrhmsnadel/BelTu-Agent.git
cd BelTu-Agent
chmod +x BelTu-Agent.sh
```

### 2. Make the script executable

When the repository is copied from an archive or another filesystem, execute permissions may not be preserved. Run:

```bash
chmod +x BelTu-Agent.sh tests/test_beltu.sh
```

Verify direct execution:

```bash
./BelTu-Agent.sh --version
```

### 3. Install the `beltu` command

Recommended user-local installation:

```bash
make install-local
```

This creates:

```text
~/.local/bin/beltu -> /absolute/path/to/BelTu-Agent/BelTu-Agent.sh
```

Make sure the directory is in your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

To persist the path on Bash:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

Verify the installed command:

```bash
command -v beltu
beltu --version
```

For an explicit system-wide installation into `/usr/local/bin`:

```bash
make install
```

The system-wide target may use `sudo` because `/usr/local/bin` is normally administrator-owned. It is never invoked automatically by BelTu-Agent.

You can still run the script directly from the repository:

```bash
./BelTu-Agent.sh -t example.com -d
```

### 4. Dependencies

BelTu-Agent checks only the dependencies needed for the selected stage(s).

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

**Full pipeline / reporting**

- `jq`
- `pandoc`
- `weasyprint`

The automatic installer is not invoked by `--dry-run`.

To explicitly authorize dependency installation:

```bash
beltu -t example.com -f --install
```

With an interactive terminal, missing dependencies may be offered for installation. In non-interactive execution, unattended installation is refused unless `--install` is explicitly supplied.

`--install` and `--no-install` are mutually exclusive, and `--dry-run` cannot be combined with `--install`.

Go-installed tools use the user Go binary directory. If the native Dalfox package is unavailable, the installer uses the modern Cargo-based path rather than modifying system Python. WeasyPrint prefers an OS package and otherwise uses an isolated Python virtual environment.

## Scope safety

Use a scope file whenever a program provides an explicit allowlist:

```text
example.com
*.example.com
api.example.com
```

Run:

```bash
beltu -t example.com -f --scope scope.txt
```

A wildcard `*.example.com` covers subdomains only. List `example.com` separately when the apex domain is explicitly in scope.

BelTu-Agent applies scope in multiple places:

```text
scope validation
    -> in-scope discovery assets
    -> in-scope crawling inputs
    -> Katana native crawl-scope restriction when supported
    -> post-filter normalized URLs
    -> in-scope vulnerability targets
```

This is intentionally defense-in-depth. Raw discovery/provider output may still be retained for auditability, but out-of-scope hosts are not intentionally fed into active probing/crawling/scanning when a scope file is supplied.

The scope parser is deliberately domain-based. Its wildcard engine is structured so future exclusions such as `!admin.example.com` can be added without replacing the whole matcher.

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

### Explicit dependency installation

```bash
beltu -t example.com -f --install
```

### Disable dependency installation

```bash
beltu -t example.com -f --no-install
```

### Dry run

```bash
beltu -t example.com -f --dry-run --no-install
```

Dry run performs argument/config/scope validation and prints the planned stages and required dependency list. It does **not** execute dependency binaries, scanners, crawlers, or package installation.

These combinations are rejected:

```bash
beltu -t example.com -f --dry-run --install
beltu -t example.com -f --install --no-install
```

### Resume

```bash
beltu --resume recon_example.com_20260911_010000 -f
```

When `--resume` is supplied without a stage flag, the full pipeline is selected and already-completed modules are skipped.

### Help and version

```bash
beltu --help
beltu --version
```

## Runtime controls

The defaults are intentionally conservative:

```text
threads:                 10
rate-limit:               5
request/tool timeout:    10 seconds
retries:                  1
commix sample:           20 parameterized URLs
```

Upper bounds are enforced:

| Option | Allowed range | Default |
|---|---:|---:|
| `--threads` | `1..100` | `10` |
| `--rate-limit` | `1..1000` | `5` |
| `--timeout` | `1..300` seconds | `10` |
| `--retries` | `0..5` | `1` |
| `--max-injection-targets` | `1..100` | `20` |

`--rate-limit` and `--threads` are **per-tool request rate/concurrency controls where the selected tool supports them**. BelTu-Agent does not claim to implement a single global network-wide requests-per-second limiter.

Increasing these values never overrides the target's program rules or published rate limits.

## Configuration

Copy the example:

```bash
cp config/beltu.conf.example config/beltu.conf
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

Use:

```bash
beltu -t example.com -f --config config/beltu.conf
```

Command-line values take precedence over configuration-file values.

## Tool validation and compatibility

Finding an executable named `httpx` or `nuclei` is not considered sufficient. BelTu-Agent validates the discovered executable and checks the help/version interface for flags used by the current adapter.

The validation covers invocation-critical options for the core tools, including output handling, input-list handling, timeout/retry controls, and scanner-specific controls. A tool can therefore be reported as:

```text
[+] httpx detected
    Version: ...
```

or:

```text
[!] httpx found but validation failed
```

A validation failure does not silently turn into a fake successful scan. The affected module records the unavailable tool and continues with other independent tools where possible.

Because these are external tools, upstream CLI changes can still require an adapter update.

## Failure handling and state

Each module records one of:

```text
not_run
running
completed
partial
failed
skipped
```

A failed tool does not automatically abort unrelated tools. Critical input/output failures still stop the run early.

### Deep enumeration classification

The discovery module tracks enumeration-tool successes/failures and the HTTP probing result separately. The presence of the target seed alone does not make the module successful.

For example:

```text
subfinder failed
assetfinder failed
amass failed
httpx failed
```

is recorded as `failed`, not `partial` merely because the target seed exists.

A mixture of successful and failed components is recorded as `partial`.

## Resume and accumulated duration

State is stored in:

```text
metadata/state.tsv
```

`run.json` retains the original start time, cumulative duration, and resume count.

For example, after a previous 12-second run followed by a resume, the new duration is based on:

```text
previous accumulated duration + current resume segment
```

Completed modules are skipped. Failed or partial modules can be rerun.

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

## Tool logging

Each tool invocation records:

- UTC start/end timestamps
- Tool name
- Quoted command representation
- Result path, when applicable
- Stdout log path
- Stderr log path
- Input count
- Duration
- Exit code

For tools with an explicit `-o`/output argument, the result file is owned by the tool. BelTu-Agent captures stdout and stderr separately and does not redirect stdout into the same result path.

## URL processing

The URL pipeline retains raw provider outputs and then creates normalized, deduplicated data sets.

The parameter stage produces:

```text
urls_with_params.txt
unique_endpoints.txt
parameterized_endpoints.txt
unique_parameters.txt
```

For example:

```text
/api/user?id=1
/api/user?id=2
/api/user?id=3
```

can be represented as one endpoint plus the `id` parameter while the original URL values remain available in the raw/parameterized URL artifacts.

## Vulnerability scanning

The vulnerability module keeps the existing scanners:

```text
Nuclei Scanner
XSS Reflection Analyzer (kxss)
Dalfox XSS Scanner
Command Injection Probe (commix)
```

`commix` is intentionally bounded by `--max-injection-targets` and defaults to 20 parameterized URLs.

Every scanner records a status and exit code. A failed scanner is **not** represented as zero findings.

Automated detections are candidates for manual verification. BelTu-Agent does not invent a final severity for findings that do not provide one.

## Reporting

The report contains:

### Executive Summary

- Target
- Assessment date
- Scan mode
- Overall status

### Attack Surface

- Unique subdomains/seed hosts
- In-scope hosts
- Live hosts
- Unique URLs
- Parameterized URLs
- Unique endpoints
- Unique parameters

### Findings Summary

Nuclei severity buckets are shown from its structured output when the scanner completes:

```text
Critical
High
Medium
Low
Informational
```

A failed or skipped scanner is reported explicitly rather than interpreted as a clean result.

### Tool Coverage

The report distinguishes:

```text
validated
found, validation failed
missing
not required
```

and scanner-level status where applicable.

### Raw Evidence

The report references the raw result and log files instead of dumping unrestricted tool output into the document.

### Verification Guidance

Automated results require manual reproduction, scope confirmation, impact validation, and final severity assessment before disclosure or remediation.

## `run.json`

Each run includes machine-readable metadata similar to:

```json
{
  "tool": "BelTu-Agent",
  "version": "1.1.2",
  "target": "example.com",
  "started_at": "2026-09-11T00:00:00Z",
  "finished_at": "2026-09-11T00:02:10Z",
  "mode": "full",
  "status": "completed",
  "dry_run": 0,
  "scope_file": "metadata/scope.txt",
  "output_directory": "recon_example.com_20260911_000000",
  "duration_seconds": 130,
  "resume_count": 0
}
```

The file also includes module statuses, attack-surface statistics, and scanner statuses.

## Testing

The project includes a dependency-free Bash regression suite:

```bash
./tests/test_beltu.sh
```

It covers:

- Bash syntax
- `--version` and `--help`
- target validation
- shell metacharacter rejection
- module selection
- dependency mapping
- dry-run/install conflicts
- dry-run side-effect protection against dependency execution
- numeric bounds
- scope matching and filtering
- Katana native scope pattern generation
- `run_tool_output_arg` output separation
- deep enumeration failure classification
- resume duration/state handling
- README consistency checks

ShellCheck is run automatically by the test suite when the `shellcheck` executable is available.

## Screenshots

Add real screenshots after testing the project in your own environment:

```text
docs/screenshots/
├── cli-dry-run.png
├── full-pipeline.png
└── report-overview.png
```

The repository does not claim screenshots that were not actually captured.

## Troubleshooting

### `beltu: command not found`

Check whether the user-local command exists:

```bash
ls -l ~/.local/bin/beltu
command -v beltu
```

If it exists but is not found, add the local bin directory to your current shell:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then verify:

```bash
beltu --version
```

If the direct script reports `Permission denied`, restore its execute bit:

```bash
chmod +x BelTu-Agent.sh
```

Then reinstall the user-local command:

```bash
make install-local
```

### `httpx found but validation failed`

Make sure the executable is ProjectDiscovery `httpx`, not another program named `httpx`:

```bash
command -v httpx
httpx -version
```

### `--dry-run` refuses `--install`

This is intentional. Dry run is designed to avoid installation and scanning side effects:

```bash
beltu -t example.com -f --dry-run --no-install
```

### Scope blocks a host

Check the scope file. For a wildcard entry such as:

```text
*.example.com
```

remember that the apex `example.com` is not covered by that wildcard entry and must be listed separately when required.

### A scanner shows `failed` instead of `0 findings`

Open the corresponding stderr/tool log. BelTu-Agent keeps scanner errors visible and does not convert them into a zero-finding claim.

### Resume metadata is missing

The resume directory must contain at least:

```text
metadata/target.txt
metadata/state.tsv
```

`metadata/run.json` is used when available to preserve accumulated duration and resume count.

### Go tools install but are not found in future shells

Persist the Go user bin directory if needed:

```bash
echo 'export PATH="$HOME/go/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### PDF is missing

Check that both `pandoc` and `weasyprint` are available and inspect:

```text
logs/tools/report_pandoc.stderr.log
logs/tools/report_weasyprint.stderr.log
```

## Limitations

- External security tools can change their CLI interfaces upstream.
- Historical URL sources can return stale or duplicate data.
- Automated findings are not proof of exploitability.
- Parameter mining is intentionally lightweight and does not replace manual application mapping.
- Scope matching is domain-oriented and intentionally does not implement arbitrary program-specific wildcard syntax.
- `commix` is deliberately bounded.
- `--rate-limit` is not a global network-wide limiter; it is passed to individual tools where those tools support the relevant control.

## Roadmap

- Additional fixture-based URL parser tests
- Optional local CSV/SARIF exports
- Local per-program rate-limit profiles
- More resilient adapter checks as upstream CLIs evolve
- Explicit scope exclusion rules such as `!admin.example.com`

## License

MIT. See [`LICENSE`](LICENSE).

## Legal disclaimer

You are solely responsible for ensuring that you have permission to test every target. This project is intended for authorized security assessments, bug bounty programs, labs, and environments where the operator has explicit authorization.

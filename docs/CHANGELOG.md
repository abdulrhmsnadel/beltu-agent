# Changelog

## 1.1.3

- Remove the optional runtime allowlist interface and apply a consistent built-in target-domain boundary to discovered assets, crawler seeds, historical URLs, and vulnerability-scanner targets.
- Fix Dalfox file-input syntax and treat exit code 1 as a successful scan that reported findings; input/runtime errors remain failures.
- Align the README with the Bash CLI actually present in this repository.
- Add a Shell CI workflow and configure CodeQL to analyze GitHub Actions workflows.

## 1.1.2

Focused installability/runtime-entrypoint fix.

- Ensure `BelTu-Agent.sh` is executable in the release artifact.
- Make `make install-local` restore executable permissions before creating `~/.local/bin/beltu`.
- Add explicit system-wide `make install` and uninstall targets.
- Add `make doctor` for basic command-entrypoint diagnostics without executing security tools.
- Update installation and troubleshooting documentation for PATH and execute-permission issues.

## 1.1.1

- Fixed `run_tool_output_arg` so tool-owned `-o` output is separated from captured stdout/stderr.
- Prevented `--dry-run` from validating binaries or installing dependencies; `--dry-run --install` is rejected.
- Rejected conflicting `--install --no-install` combinations.
- Enforced target-domain filtering before crawling and added Katana native target restrictions where supported, while retaining post-filtering.
- Clarified that request-rate and concurrency settings are per-tool where supported.
- Fixed deep-enum status classification so a target seed cannot make a fully failed enumeration look successful.
- Added bounded validation for numeric runtime controls.
- Preserved accumulated run duration across resumes and added resume count metadata.
- Added tests for dry-run/install conflicts, target-domain filtering, failure classification, bounds, resume timing, and tool output handling.
- Strengthened current CLI compatibility checks for core tools without introducing a new architecture.

## 1.1.0

- Added module-specific dependency mapping.
- Added tool identity/version/basic-execution validation.
- Added explicit dependency installation via `--install` and `--no-install`.
- Added target-host validation and filtering.
- Added rate-limit, timeout, retry, thread, and commix target controls.
- Added module state and resumable runs.
- Added structured per-tool logs.
- Added URL normalization, endpoint extraction, and unique parameter extraction.
- Added HTML/PDF reporting with scanner-failure distinction.
- Added `run.json` metadata and statistics.
- Added tests, configuration example, architecture notes, and GitHub-ready files.
- Aligned current tool adapters with upstream CLI changes for Amass, gau, and Dalfox.
- Made explicit `--install` override a config-file `NO_INSTALL=1` setting.

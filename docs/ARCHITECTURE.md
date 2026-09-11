# BelTu-Agent Architecture Notes

## Design principles

1. **Do not fail closed on ordinary tool errors.** Individual tool failures are recorded and the pipeline continues where possible.
2. **Fail early on critical operator errors.** Invalid targets, unreadable scope files, and unwritable output directories stop the run.
3. **No `eval`.** Commands are represented as Bash arrays and executed directly.
4. **Scope before active stages.** When a scope file is supplied, only in-scope assets feed active probing/crawling/scanning.
5. **Raw evidence stays accessible.** Each external tool keeps a raw output file in the run directory.
6. **Automation is not confirmation.** The report explicitly separates automated detections from manual verification.

## Module contracts

### `deep_enum`

Inputs: `TARGET`, optional scope.

Outputs:

- `subdomains/*.txt`
- `all_subdomains.txt`
- `scoped_subdomains.txt`
- `httpx_results.jsonl`
- `live_hosts.txt`

### `url_crawl`

Uses `live_hosts.txt` from discovery when available; otherwise falls back to the target URL.

Outputs:

- raw crawler/provider results
- normalized `all_urls.txt`
- `urls_with_params.txt`
- `unique_endpoints.txt`
- `parameterized_endpoints.txt`
- `unique_parameters.txt`

### `vuln_scan`

Uses live hosts as primary nuclei inputs and parameterized URLs for kxss/dalfox/commix. Commix is bounded by `MAX_INJECTION_TARGETS`.

### `report`

Reads local artifacts only. No external API is used by BelTu-Agent itself.

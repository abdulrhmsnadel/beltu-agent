#!/usr/bin/env bash
#
# ============================================================================
# BelTu-Agent — Recon & Vulnerability Scanning Orchestrator
# Version: 1.1.1
# Purpose: Authorized security testing / bug bounty recon automation ONLY.
# ============================================================================

set -uo pipefail
IFS=$'\n\t'

SCRIPT_NAME="BelTu-Agent"
SCRIPT_VERSION="1.1.1"
SCRIPT_COMMAND="beltu"

GOBIN_DIR="${GOBIN:-${GOPATH:-$HOME/go}/bin}"
CARGO_BIN_DIR="${CARGO_HOME:-$HOME/.cargo}/bin"
export PATH="$PATH:$GOBIN_DIR:$CARGO_BIN_DIR:$HOME/.local/bin:/usr/local/go/bin"

# -----------------------------------------------------------------------------
# Runtime configuration
# -----------------------------------------------------------------------------
TARGET=""
TARGET_RAW=""
SCOPE_FILE=""
CONFIG_FILE=""
RESUME_DIR=""
OUTDIR=""
RUN_ID=""
RUN_TIMESTAMP=""
STARTED_EPOCH=0
STARTED_ISO=""
FINISHED_EPOCH=0
ACCUMULATED_DURATION=0
ORIGINAL_STARTED_ISO=""
RESUME_COUNT=0

MODE_DEEP=0
MODE_URL=0
MODE_VULN=0
MODE_FULL=0
MODE_REPORT_REQUESTED=0

THREADS=10
RATE_LIMIT=5
TIMEOUT=10
RETRIES=1
MAX_INJECTION_TARGETS=20

# Conservative upper bounds for numeric controls.
MAX_THREADS=100
MAX_RATE_LIMIT=1000
MAX_TIMEOUT=300
MAX_RETRIES=5
MAX_INJECTION_TARGETS_LIMIT=100

DRY_RUN=0
NO_INSTALL=0
INSTALL_REQUESTED=0
VERBOSE=0
CRITICAL_FAILURE=0
FINAL_RC=0
INTERRUPTED=0

# CLI explicit-value tracking so config cannot silently overwrite flags.
CLI_THREADS_SET=0
CLI_RATE_LIMIT_SET=0
CLI_TIMEOUT_SET=0
CLI_RETRIES_SET=0
CLI_MAX_INJECTION_TARGETS_SET=0
CLI_NO_INSTALL_SET=0
CLI_VERBOSE_SET=0

# Paths initialized after the run directory exists.
TMP_DIR=""
LOG_ROOT=""
TOOL_LOG_ROOT=""
STATE_FILE=""
RUN_JSON=""

# Module status values: not_run/running/completed/partial/failed/skipped.
DEEP_STATUS="not_run"
URL_STATUS="not_run"
VULN_STATUS="not_run"
REPORT_STATUS="not_run"

# Scanner-specific statuses for accurate reporting.
NUCLEI_STATUS="not_run"
KXSS_STATUS="not_run"
DALFOX_STATUS="not_run"
COMMIX_STATUS="not_run"

# Dependency tracking.
declare -a REQUIRED_TOOLS=()
declare -a TOOL_OK=()
declare -a TOOL_BAD=()
declare -a TOOL_MISSING=()

# Colors.
C_RED='\033[0;31m'
C_GRN='\033[0;32m'
C_YLW='\033[1;33m'
C_BLU='\033[0;34m'
C_CYN='\033[0;36m'
C_RST='\033[0m'
C_BLD='\033[1m'

# -----------------------------------------------------------------------------
# UI / generic helpers
# -----------------------------------------------------------------------------
log()  { printf '%b[*]%b %s\n' "$C_CYN" "$C_RST" "$*"; }
ok()   { printf '%b[+]%b %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%b[!]%b %s\n' "$C_YLW" "$C_RST" "$*" >&2; }
err()  { printf '%b[x]%b %s\n' "$C_RED" "$C_RST" "$*" >&2; }
hdr()  { printf '\n%b%b==== %s ====%b\n\n' "$C_BLD" "$C_BLU" "$*" "$C_RST"; }

usage() {
    printf '%b\n' "${C_BLD}$SCRIPT_NAME v$SCRIPT_VERSION${C_RST}"
    cat <<EOF_USAGE
Authorized reconnaissance and vulnerability-scanning orchestrator.

Usage:
  $SCRIPT_COMMAND -t <domain> [MODE] [OPTIONS]
  $0 -t <domain> -f

Legacy modes (kept compatible):
  -d                    Deep subdomain enumeration + live host probing
  -a                    Crawling + historical URLs + parameter mining
  -v                    Automated vulnerability checks
  -f                    Full pipeline: -d -> -a -> -v -> reports

Target / scope:
  -t, --target DOMAIN  Bare domain/subdomain only, e.g. example.com
      --scope FILE     Scope allowlist: exact domains and *.example.com

Execution:
      --threads N      Concurrency hint (default: $THREADS)
      --rate-limit N   Per-tool request rate/concurrency control where supported (default: $RATE_LIMIT)
      --timeout N      Request/tool timeout in seconds (default: $TIMEOUT)
      --retries N      Retries where supported (default: $RETRIES)
      --max-injection-targets N
                        Maximum parameterized URLs given to commix (default: $MAX_INJECTION_TARGETS)
      --config FILE    Configuration file (KEY=VALUE)
      --resume DIR     Resume an existing BelTu-Agent output directory
      --install        Install missing dependencies after explicit request
      --no-install     Never install dependencies
      --dry-run        Validate and print the stage plan; do not scan
      --verbose        Verbose BelTu-Agent messages

General:
  -h, --help           Show this help
      --version        Show version

Examples:
  $SCRIPT_COMMAND -t example.com -d
  $SCRIPT_COMMAND -t example.com -a --scope scope.txt
  $SCRIPT_COMMAND -t example.com -v --rate-limit 3 --threads 5
  $SCRIPT_COMMAND -t example.com -f --scope scope.txt
  $SCRIPT_COMMAND -t example.com -f --install
  $SCRIPT_COMMAND --resume recon_example.com_20260911_010000
  $SCRIPT_COMMAND -t example.com -d --dry-run

Scope format:
  example.com
  *.example.com
  api.example.com

A wildcard entry covers subdomains only; list the apex domain separately if
it is explicitly in scope.
EOF_USAGE
}

print_banner() {
    printf '%b' "$C_BLD$C_CYN"
    cat <<'EOF_BANNER'
 ____       _ _____       _                    _
|  _ \ ___ | |_   _|   __| |    __ _  __ _  ___| |_
| |_) / _ \| | | |___ / _` |   / _` |/ _` |/ _ \ __|
|  _ < (_) | | | |___| (_| |  | (_| | (_| |  __/ |_
|_| \_\___/|_| |_|    \__,_|   \__,_|\__, |\___|\__|
                                     |___/
        BelTu-Agent :: Recon & VulnScan Orchestrator
EOF_BANNER
    printf '%b\n' "$C_RST"
    printf 'Version %s | command: %s\n' "$SCRIPT_VERSION" "$SCRIPT_COMMAND"
}

now_iso() { date '+%Y-%m-%dT%H:%M:%S%z'; }
utc_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

elapsed_seconds() {
    local start="$1" end="$2"
    printf '%s' "$((end - start))"
}

count_lines() {
    local file="$1"
    if [[ -s "$file" ]]; then
        wc -l < "$file" | tr -d '[:space:]'
    else
        printf '0'
    fi
}

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\t'/\\t}
    value=${value//$'\r'/\\r}
    value=${value//$'\n'/\\n}
    printf '%s' "$value"
}

trim_ws() {
    printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

is_integer() { [[ "$1" =~ ^[0-9]+$ ]]; }

validate_bounded_int() {
    local name="$1" var_name="$2" min="$3" max="$4" value raw
    raw="${!var_name}"
    if ! is_integer "$raw"; then
        err "$name must be an integer between $min and $max: '$raw'"
        return 1
    fi
    value="$(printf '%s' "$raw" | sed 's/^0*//')"
    [[ -n "$value" ]] || value=0
    # Keep arithmetic operands small enough to avoid shell integer overflow.
    if (( ${#value} > ${#max} )); then
        err "$name must be between $min and $max: '$raw'"
        return 1
    fi
    if (( value < min || value > max )); then
        err "$name must be between $min and $max: '$raw'"
        return 1
    fi
    printf -v "$2" '%s' "$value"
    return 0
}

validate_runtime_options() {
    validate_bounded_int "--threads" THREADS 1 "$MAX_THREADS" || return 1
    validate_bounded_int "--rate-limit" RATE_LIMIT 1 "$MAX_RATE_LIMIT" || return 1
    validate_bounded_int "--timeout" TIMEOUT 1 "$MAX_TIMEOUT" || return 1
    validate_bounded_int "--retries" RETRIES 0 "$MAX_RETRIES" || return 1
    validate_bounded_int "--max-injection-targets" MAX_INJECTION_TARGETS 1 "$MAX_INJECTION_TARGETS_LIMIT" || return 1
    case "$NO_INSTALL" in 0|1) ;; *) err "NO_INSTALL must be 0 or 1."; return 1 ;; esac
    case "$VERBOSE" in 0|1) ;; *) err "VERBOSE must be 0 or 1."; return 1 ;; esac
    return 0
}

# -----------------------------------------------------------------------------
# Target and scope validation
# -----------------------------------------------------------------------------
sanitize_domain() {
    local raw="$1" clean="$1"

    if [[ -z "$clean" ]]; then
        err "Target cannot be empty."
        return 1
    fi
    if [[ "$clean" =~ [[:space:]] ]]; then
        err "Target must not contain whitespace."
        return 1
    fi
    if [[ ! "$clean" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; then
        err "Invalid target format: '$raw'"
        err "Only a bare domain/subdomain is accepted (example.com or sub.example.com)."
        return 1
    fi
    case "$clean" in
        *[\;\|\&\$\`\(\)\<\>\"\'\\\*\?\ ]*)
            err "Rejected target containing disallowed shell characters."
            return 1
            ;;
    esac
    if (( ${#clean} > 253 )); then
        err "Target is too long for a DNS hostname."
        return 1
    fi
    printf '%s' "${clean,,}"
}

validate_scope_pattern() {
    local raw="$1" pattern
    pattern="$(trim_ws "$raw")"
    [[ -z "$pattern" ]] && return 0
    [[ "${pattern:0:1}" == '#' ]] && return 0

    if [[ "$pattern" == \*.* ]]; then
        pattern="${pattern#*.}"
        [[ -n "$pattern" ]] || return 1
    elif [[ "$pattern" == \** ]]; then
        return 1
    fi

    sanitize_domain "$pattern" >/dev/null 2>&1
}

scope_pattern_match() {
    local host="$1" pattern="$2" suffix
    host="${host,,}"
    pattern="${pattern,,}"
    if [[ "$pattern" == \*.* ]]; then
        suffix="${pattern#*.}"
        [[ -n "$suffix" ]] || return 1
        [[ "$host" == *."$suffix" && "$host" != "$suffix" ]]
        return
    fi
    [[ "$host" == "$pattern" ]]
}

is_in_scope() {
    local host="$1" line pattern
    [[ -z "$SCOPE_FILE" ]] && return 0
    [[ -r "$SCOPE_FILE" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        pattern="$(trim_ws "${line%%#*}")"
        [[ -z "$pattern" ]] && continue
        scope_pattern_match "$host" "$pattern" && return 0
    done < "$SCOPE_FILE"
    return 1
}

validate_scope_file() {
    local line num=0 pattern
    [[ -z "$SCOPE_FILE" ]] && return 0
    [[ -f "$SCOPE_FILE" ]] || { err "Scope file not found: $SCOPE_FILE"; return 1; }
    [[ -r "$SCOPE_FILE" ]] || { err "Scope file is not readable: $SCOPE_FILE"; return 1; }

    while IFS= read -r line || [[ -n "$line" ]]; do
        num=$((num + 1))
        pattern="$(trim_ws "${line%%#*}")"
        [[ -z "$pattern" ]] && continue
        if ! validate_scope_pattern "$pattern"; then
            err "Invalid scope entry at line $num: '$pattern'"
            return 1
        fi
    done < "$SCOPE_FILE"

    if ! is_in_scope "$TARGET"; then
        err "Target '$TARGET' is outside the provided scope."
        err "Add the apex domain or an appropriate wildcard entry to scope.txt."
        return 1
    fi
    ok "Scope validated: $TARGET is in scope"
}

host_from_url() {
    local url="$1" rest authority hostport host
    case "$url" in
        http://*|https://*)
            rest="${url#*://}"
            authority="${rest%%[/?]*}"
            [[ "$authority" == "$rest" ]] && authority="$rest"
            hostport="${authority##*@}"
            if [[ "$hostport" == \[*\]* ]]; then
                host="${hostport#\[}"
                host="${host%%\]*}"
            else
                host="${hostport%%:*}"
            fi
            printf '%s' "${host,,}"
            ;;
        *)
            printf '%s' ""
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Filesystem / run state
# -----------------------------------------------------------------------------
ensure_dir() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        [[ -w "$dir" ]] || { err "Directory is not writable: $dir"; return 1; }
        return 0
    fi
    mkdir -p -- "$dir" || { err "Cannot create directory: $dir"; return 1; }
    [[ -w "$dir" ]] || { err "Directory is not writable: $dir"; return 1; }
}

init_output_tree() {
    ensure_dir "$OUTDIR" || return 1
    local dir
    for dir in \
        "$OUTDIR/metadata" \
        "$OUTDIR/subdomains" \
        "$OUTDIR/urls" \
        "$OUTDIR/vulnerabilities" \
        "$OUTDIR/logs" \
        "$OUTDIR/logs/tools"; do
        ensure_dir "$dir" || return 1
    done
    LOG_ROOT="$OUTDIR/logs"
    TOOL_LOG_ROOT="$OUTDIR/logs/tools"
    STATE_FILE="$OUTDIR/metadata/state.tsv"
    RUN_JSON="$OUTDIR/metadata/run.json"
    touch "$STATE_FILE" || { err "Cannot initialize state file: $STATE_FILE"; return 1; }
}

init_temp() {
    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beltu.XXXXXXXX")" || {
        err "Unable to create temporary directory."
        return 1
    }
}

cleanup() {
    local rc="$?"
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf -- "$TMP_DIR"
    fi
    return "$rc"
}

handle_signal() {
    local sig="$1"
    INTERRUPTED=1
    FINAL_RC=130
    FINISHED_EPOCH="$(date +%s)"
    warn "Received $sig; stopping current stage cleanly."
    if [[ -n "$RUN_JSON" && -d "$OUTDIR" ]]; then
        write_run_json || :
    fi
    exit 130
}

write_state() {
    local module="$1" status="$2" start="$3" end="$4" rc="$5" note="${6:-}"
    local tmp_state="$TMP_DIR/state.${module}.tmp"
    [[ -f "$STATE_FILE" ]] || : > "$STATE_FILE"
    awk -F '\t' -v m="$module" '$1 != m' "$STATE_FILE" > "$tmp_state" 2>/dev/null || :
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$module" "$status" "$start" "$end" "$rc" "$note" >> "$tmp_state" || return 1
    mv -f -- "$tmp_state" "$STATE_FILE" || return 1
}

state_is_completed() {
    local module="$1" _module status _start _end _rc _note
    [[ -f "$STATE_FILE" ]] || return 1
    while IFS=$'\t' read -r _module status _start _end _rc _note; do
        [[ "$_module" == "$module" && "$status" == "completed" ]] && return 0
    done < "$STATE_FILE"
    return 1
}

module_current_status() {
    local module="$1" _module status _start _end _rc _note
    [[ -f "$STATE_FILE" ]] || { printf 'not_run'; return; }
    while IFS=$'\t' read -r _module status _start _end _rc _note; do
        if [[ "$_module" == "$module" ]]; then
            printf '%s' "$status"
            return
        fi
    done < "$STATE_FILE"
    printf 'not_run'
}

mode_label() {
    if (( MODE_FULL == 1 )); then
        printf 'full'
        return
    fi
    local label=""
    (( MODE_DEEP == 1 )) && label="deep"
    (( MODE_URL == 1 )) && label="${label:+$label,}crawl"
    (( MODE_VULN == 1 )) && label="${label:+$label,}vuln"
    printf '%s' "$label"
}

aggregate_status() {
    if (( INTERRUPTED == 1 )); then
        printf 'partial'
        return
    fi
    if (( DRY_RUN == 1 )); then
        printf 'dry-run'
        return
    fi
    if (( CRITICAL_FAILURE == 1 )); then
        printf 'failed'
        return
    fi
    local s status="completed"
    for s in "$DEEP_STATUS" "$URL_STATUS" "$VULN_STATUS" "$REPORT_STATUS"; do
        case "$s" in
            partial|failed|running) status="partial" ;;
        esac
    done
    printf '%s' "$status"
}

write_config_snapshot() {
    local config_out="$OUTDIR/metadata/config.txt"
    {
        printf 'BelTu-Agent %s\n' "$SCRIPT_VERSION"
        printf 'target=%s\n' "$TARGET"
        printf 'mode=%s\n' "$(mode_label)"
        printf 'scope=%s\n' "${SCOPE_FILE:-none}"
        printf 'threads=%s\n' "$THREADS"
        printf 'rate_limit=%s\n' "$RATE_LIMIT"
        printf 'timeout=%s\n' "$TIMEOUT"
        printf 'retries=%s\n' "$RETRIES"
        printf 'max_injection_targets=%s\n' "$MAX_INJECTION_TARGETS"
        printf 'dry_run=%s\n' "$DRY_RUN"
        printf 'no_install=%s\n' "$NO_INSTALL"
    } > "$config_out" || return 1
}

write_run_json() {
    [[ -z "$RUN_JSON" || ! -d "$OUTDIR" ]] && return 0
    local finished_at="" duration status
    (( FINISHED_EPOCH > 0 )) && finished_at="$(utc_iso)"
    if (( STARTED_EPOCH > 0 )); then
        if (( FINISHED_EPOCH > 0 )); then
            duration="$((ACCUMULATED_DURATION + FINISHED_EPOCH - STARTED_EPOCH))"
        else
            duration="$((ACCUMULATED_DURATION + $(date +%s) - STARTED_EPOCH))"
        fi
    else
        duration="$ACCUMULATED_DURATION"
    fi
    status="$(aggregate_status)"
    [[ -n "$STARTED_ISO" ]] || STARTED_ISO="$(utc_iso)"
    [[ -n "$ORIGINAL_STARTED_ISO" ]] || ORIGINAL_STARTED_ISO="$STARTED_ISO"

    {
        printf '{\n'
        printf '  "tool": "%s",\n' "$(json_escape "$SCRIPT_NAME")"
        printf '  "version": "%s",\n' "$(json_escape "$SCRIPT_VERSION")"
        printf '  "target": "%s",\n' "$(json_escape "$TARGET")"
        printf '  "started_at": "%s",\n' "$(json_escape "$ORIGINAL_STARTED_ISO")"
        printf '  "resume_count": %s,\n' "$RESUME_COUNT"
        printf '  "finished_at": "%s",\n' "$(json_escape "$finished_at")"
        printf '  "mode": "%s",\n' "$(json_escape "$(mode_label)")"
        printf '  "status": "%s",\n' "$(json_escape "$status")"
        printf '  "dry_run": %s,\n' "$DRY_RUN"
        printf '  "scope_file": "%s",\n' "$(json_escape "$SCOPE_FILE")"
        printf '  "output_directory": "%s",\n' "$(json_escape "$OUTDIR")"
        printf '  "duration_seconds": %s,\n' "$duration"
        printf '  "modules": {\n'
        printf '    "deep_enum": "%s",\n' "$DEEP_STATUS"
        printf '    "url_crawl": "%s",\n' "$URL_STATUS"
        printf '    "vuln_scan": "%s",\n' "$VULN_STATUS"
        printf '    "report": "%s"\n' "$REPORT_STATUS"
        printf '  },\n'
        printf '  "statistics": {\n'
        printf '    "subdomains_discovered": %s,\n' "$(count_lines "$OUTDIR/subdomains/all_subdomains.txt")"
        printf '    "scoped_subdomains": %s,\n' "$(count_lines "$OUTDIR/subdomains/scoped_subdomains.txt")"
        printf '    "live_hosts": %s,\n' "$(count_lines "$OUTDIR/subdomains/live_hosts.txt")"
        printf '    "urls": %s,\n' "$(count_lines "$OUTDIR/urls/all_urls.txt")"
        printf '    "parameterized_urls": %s,\n' "$(count_lines "$OUTDIR/urls/urls_with_params.txt")"
        printf '    "unique_endpoints": %s,\n' "$(count_lines "$OUTDIR/urls/unique_endpoints.txt")"
        printf '    "unique_parameters": %s,\n' "$(count_lines "$OUTDIR/urls/unique_parameters.txt")"
        printf '    "nuclei_records": %s\n' "$(count_lines "$OUTDIR/vulnerabilities/nuclei_results.jsonl")"
        printf '  },\n'
        printf '  "scanner_status": {\n'
        printf '    "nuclei": "%s",\n' "$NUCLEI_STATUS"
        printf '    "kxss": "%s",\n' "$KXSS_STATUS"
        printf '    "dalfox": "%s",\n' "$DALFOX_STATUS"
        printf '    "commix": "%s"\n' "$COMMIX_STATUS"
        printf '  }\n'
        printf '}\n'
    } > "$RUN_JSON"
}

setup_new_run() {
    RUN_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    RUN_ID="recon_${TARGET}_${RUN_TIMESTAMP}"
    OUTDIR="$RUN_ID"
    local suffix=1
    while [[ -e "$OUTDIR" ]]; do
        OUTDIR="${RUN_ID}_${suffix}"
        suffix=$((suffix + 1))
    done
    RUN_ID="$(basename "$OUTDIR")"
    init_output_tree || return 1
    printf '%s\n' "$TARGET" > "$OUTDIR/metadata/target.txt" || return 1
    if [[ -n "$SCOPE_FILE" ]]; then
        cp -- "$SCOPE_FILE" "$OUTDIR/metadata/scope.txt" || { err "Unable to snapshot scope file."; return 1; }
        SCOPE_FILE="$OUTDIR/metadata/scope.txt"
    fi
    STARTED_EPOCH="$(date +%s)"
    STARTED_ISO="$(utc_iso)"
    ORIGINAL_STARTED_ISO="$STARTED_ISO"
    ACCUMULATED_DURATION=0
    RESUME_COUNT=0
    write_config_snapshot || return 1
    write_run_json
}

load_resume_run() {
    local run_dir="$RESUME_DIR" target_file target_value
    [[ -d "$run_dir" ]] || { err "Resume directory not found: $run_dir"; return 1; }
    [[ -f "$run_dir/metadata/target.txt" ]] || { err "Resume metadata missing: $run_dir/metadata/target.txt"; return 1; }

    target_file="$run_dir/metadata/target.txt"
    target_value="$(tr -d '\r\n' < "$target_file")"
    TARGET="$(sanitize_domain "$target_value")" || return 1
    OUTDIR="$run_dir"
    RUN_ID="$(basename "$run_dir")"
    init_output_tree || return 1

    if [[ -z "$SCOPE_FILE" && -f "$run_dir/metadata/scope.txt" ]]; then
        SCOPE_FILE="$run_dir/metadata/scope.txt"
    fi

    ORIGINAL_STARTED_ISO="$(sed -n 's/^[[:space:]]*"started_at":[[:space:]]*"\([^"]*\)".*/\1/p' "$run_dir/metadata/run.json" 2>/dev/null | head -n 1 || true)"
    local previous_duration previous_runs
    previous_duration="$(sed -n 's/^[[:space:]]*"duration_seconds":[[:space:]]*\([0-9][0-9]*\),\{0,1\}.*/\1/p' "$run_dir/metadata/run.json" 2>/dev/null | head -n 1 || true)"
    previous_runs="$(sed -n 's/^[[:space:]]*"resume_count":[[:space:]]*\([0-9][0-9]*\),\{0,1\}.*/\1/p' "$run_dir/metadata/run.json" 2>/dev/null | head -n 1 || true)"
    [[ "$previous_duration" =~ ^[0-9]+$ ]] && ACCUMULATED_DURATION="$previous_duration" || ACCUMULATED_DURATION=0
    [[ "$previous_runs" =~ ^[0-9]+$ ]] && RESUME_COUNT=$((previous_runs + 1)) || RESUME_COUNT=1
    STARTED_EPOCH="$(date +%s)"
    STARTED_ISO="$ORIGINAL_STARTED_ISO"
    [[ -n "$STARTED_ISO" ]] || STARTED_ISO="$(utc_iso)"
    DEEP_STATUS="$(module_current_status deep_enum)"
    URL_STATUS="$(module_current_status url_crawl)"
    VULN_STATUS="$(module_current_status vuln_scan)"
    REPORT_STATUS="$(module_current_status report)"
    ok "Resume state: deep=$DEEP_STATUS crawl=$URL_STATUS vuln=$VULN_STATUS report=$REPORT_STATUS"
}

# -----------------------------------------------------------------------------
# Configuration / CLI
# -----------------------------------------------------------------------------
load_config_file() {
    local file="$1" line raw key value
    [[ -f "$file" ]] || { err "Config file not found: $file"; return 1; }
    [[ -r "$file" ]] || { err "Config file not readable: $file"; return 1; }

    while IFS= read -r line || [[ -n "$line" ]]; do
        raw="$(trim_ws "${line%%#*}")"
        [[ -z "$raw" ]] && continue
        [[ "$raw" == *=* ]] || { warn "Ignoring malformed config line: $line"; continue; }
        key="$(trim_ws "${raw%%=*}")"
        value="$(trim_ws "${raw#*=}")"
        value="${value#\"}"; value="${value%\"}"
        value="${value#\'}"; value="${value%\'}"
        case "$key" in
            THREADS) [[ $CLI_THREADS_SET -eq 0 ]] && THREADS="$value" ;;
            RATE_LIMIT) [[ $CLI_RATE_LIMIT_SET -eq 0 ]] && RATE_LIMIT="$value" ;;
            TIMEOUT) [[ $CLI_TIMEOUT_SET -eq 0 ]] && TIMEOUT="$value" ;;
            RETRIES) [[ $CLI_RETRIES_SET -eq 0 ]] && RETRIES="$value" ;;
            MAX_INJECTION_TARGETS) [[ $CLI_MAX_INJECTION_TARGETS_SET -eq 0 ]] && MAX_INJECTION_TARGETS="$value" ;;
            NO_INSTALL) [[ $CLI_NO_INSTALL_SET -eq 0 && $INSTALL_REQUESTED -eq 0 ]] && NO_INSTALL="$value" ;;
            VERBOSE) [[ $CLI_VERBOSE_SET -eq 0 ]] && VERBOSE="$value" ;;
            *) warn "Unknown config key ignored: $key" ;;
        esac
    done < "$file"
}

preprocess_short_clusters() {
    local arg cluster ch
    local -a out=()
    for arg in "$@"; do
        if [[ "$arg" =~ ^-[davf]{2,}$ ]]; then
            cluster="${arg:1}"
            while [[ -n "$cluster" ]]; do
                ch="${cluster:0:1}"
                cluster="${cluster:1}"
                out+=("-$ch")
            done
        else
            out+=("$arg")
        fi
    done
    printf '%s\n' "${out[@]}"
}

parse_args() {
    local arg ch
    while (($# > 0)); do
        arg="$1"
        case "$arg" in
            -t|--target)
                shift; (($# > 0)) || { err "$arg requires a value."; return 1; }; TARGET_RAW="$1" ;;
            --target=*) TARGET_RAW="${arg#*=}" ;;
            -d) MODE_DEEP=1 ;;
            -a) MODE_URL=1 ;;
            -v) MODE_VULN=1 ;;
            -f) MODE_FULL=1 ;;
            --scope) shift; (($# > 0)) || { err "--scope requires a file."; return 1; }; SCOPE_FILE="$1" ;;
            --scope=*) SCOPE_FILE="${arg#*=}" ;;
            --config) shift; (($# > 0)) || { err "--config requires a file."; return 1; }; CONFIG_FILE="$1" ;;
            --config=*) CONFIG_FILE="${arg#*=}" ;;
            --resume) shift; (($# > 0)) || { err "--resume requires a directory."; return 1; }; RESUME_DIR="$1" ;;
            --resume=*) RESUME_DIR="${arg#*=}" ;;
            --threads) shift; (($# > 0)) || { err "--threads requires a number."; return 1; }; THREADS="$1"; CLI_THREADS_SET=1 ;;
            --threads=*) THREADS="${arg#*=}"; CLI_THREADS_SET=1 ;;
            --rate-limit) shift; (($# > 0)) || { err "--rate-limit requires a number."; return 1; }; RATE_LIMIT="$1"; CLI_RATE_LIMIT_SET=1 ;;
            --rate-limit=*) RATE_LIMIT="${arg#*=}"; CLI_RATE_LIMIT_SET=1 ;;
            --timeout) shift; (($# > 0)) || { err "--timeout requires a number."; return 1; }; TIMEOUT="$1"; CLI_TIMEOUT_SET=1 ;;
            --timeout=*) TIMEOUT="${arg#*=}"; CLI_TIMEOUT_SET=1 ;;
            --retries) shift; (($# > 0)) || { err "--retries requires a number."; return 1; }; RETRIES="$1"; CLI_RETRIES_SET=1 ;;
            --retries=*) RETRIES="${arg#*=}"; CLI_RETRIES_SET=1 ;;
            --max-injection-targets) shift; (($# > 0)) || { err "--max-injection-targets requires a number."; return 1; }; MAX_INJECTION_TARGETS="$1"; CLI_MAX_INJECTION_TARGETS_SET=1 ;;
            --max-injection-targets=*) MAX_INJECTION_TARGETS="${arg#*=}"; CLI_MAX_INJECTION_TARGETS_SET=1 ;;
            --install) INSTALL_REQUESTED=1 ;;
            --no-install) NO_INSTALL=1; CLI_NO_INSTALL_SET=1 ;;
            --dry-run) DRY_RUN=1 ;;
            --verbose) VERBOSE=1; CLI_VERBOSE_SET=1 ;;
            --version|-V) printf '%s v%s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"; exit 0 ;;
            --help|-h) usage; exit 0 ;;
            -t?*) TARGET_RAW="${arg:2}" ;;
            -[davf])
                ch="${arg:1}"
                case "$ch" in
                    d) MODE_DEEP=1 ;; a) MODE_URL=1 ;; v) MODE_VULN=1 ;; f) MODE_FULL=1 ;;
                esac
                ;;
            --) shift; (($# == 0)) || { err "Unexpected positional arguments: $*"; return 1; }; break ;;
            -*) err "Unknown option: $arg"; return 1 ;;
            *) err "Unexpected positional argument: $arg"; return 1 ;;
        esac
        shift
    done
}

validate_core_commands() {
    local cmd
    local -a required=(awk sed grep sort wc mkdir mktemp date tr cp mv head)
    for cmd in "${required[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || { err "Critical system command missing: $cmd"; return 1; }
    done
    return 0
}

# -----------------------------------------------------------------------------
# Dependency validation and installation
# -----------------------------------------------------------------------------
package_manager() {
    if command -v apt-get >/dev/null 2>&1; then printf 'apt'
    elif command -v pacman >/dev/null 2>&1; then printf 'pacman'
    elif command -v dnf >/dev/null 2>&1; then printf 'dnf'
    elif command -v brew >/dev/null 2>&1; then printf 'brew'
    else printf 'none'
    fi
}

run_as_root() {
    if (( EUID == 0 )); then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        log "Administrator privileges may be requested by sudo for: $*"
        sudo "$@"
    else
        err "Administrator privileges are required but sudo is unavailable: $*"
        return 1
    fi
}

install_packages() {
    local pm="$1"; shift
    local -a packages=("$@")
    ((${#packages[@]} > 0)) || return 0
    if (( EUID != 0 )) && [[ "$pm" != "brew" ]] && command -v sudo >/dev/null 2>&1; then
        log "System package installation may require administrator privileges; sudo is used only for package-manager commands."
    fi
    case "$pm" in
        apt) run_as_root apt-get update && run_as_root apt-get install -y -- "${packages[@]}" ;;
        pacman) run_as_root pacman -Sy --noconfirm -- "${packages[@]}" ;;
        dnf) run_as_root dnf install -y -- "${packages[@]}" ;;
        brew) brew install "${packages[@]}" ;;
        *) err "No supported package manager is available."; return 1 ;;
    esac
}

ensure_go() {
    command -v go >/dev/null 2>&1 && return 0
    warn "Go toolchain is required for several dependencies."
    case "$(package_manager)" in
        apt) install_packages apt golang-go ;;
        pacman) install_packages pacman go ;;
        dnf) install_packages dnf golang ;;
        brew) install_packages brew go ;;
        *) err "No supported package manager found to install Go."; return 1 ;;
    esac
}

ensure_cargo() {
    command -v cargo >/dev/null 2>&1 && return 0
    warn "Cargo/Rust is required for the current Dalfox source-install fallback."
    case "$(package_manager)" in
        apt) install_packages apt cargo rustc ;;
        pacman) install_packages pacman rust ;;
        dnf) install_packages dnf cargo rust ;;
        brew) install_packages brew rust ;;
        *) err "No supported package manager found to install Rust/Cargo."; return 1 ;;
    esac
}

ensure_git() {
    command -v git >/dev/null 2>&1 && return 0
    case "$(package_manager)" in
        apt) install_packages apt git ;;
        pacman) install_packages pacman git ;;
        dnf) install_packages dnf git ;;
        brew) install_packages brew git ;;
        *) err "git is required to install commix and is not available."; return 1 ;;
    esac
}

install_weasyprint() {
    local pm="$1"
    case "$pm" in
        apt) install_packages apt weasyprint && return 0 ;;
        pacman) install_packages pacman python-weasyprint && return 0 ;;
        dnf) install_packages dnf weasyprint && return 0 ;;
        brew) install_packages brew weasyprint && return 0 ;;
    esac

    command -v python3 >/dev/null 2>&1 || { err "python3 is required for isolated WeasyPrint fallback."; return 1; }
    local root="${XDG_DATA_HOME:-$HOME/.local/share}/beltu-agent"
    local venv_dir="$root/weasyprint-venv"
    ensure_dir "$root" || return 1
    if [[ ! -x "$venv_dir/bin/python" ]]; then
        python3 -m venv "$venv_dir" || { err "Unable to create WeasyPrint virtual environment: $venv_dir"; return 1; }
    fi
    "$venv_dir/bin/python" -m pip install --upgrade pip >/dev/null 2>&1 || true
    "$venv_dir/bin/python" -m pip install weasyprint || return 1
    [[ -x "$venv_dir/bin/weasyprint" ]] || { err "WeasyPrint CLI was not created in the virtual environment."; return 1; }
    ensure_dir "$HOME/.local/bin" || return 1
    ln -sf "$venv_dir/bin/weasyprint" "$HOME/.local/bin/weasyprint" || return 1
    export PATH="$HOME/.local/bin:$PATH"
}

install_tool() {
    local tool="$1" pm
    pm="$(package_manager)"
    log "Installing dependency: $tool"
    case "$tool" in
        subfinder) ensure_go && go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest ;;
        assetfinder) ensure_go && go install -v github.com/tomnomnom/assetfinder@latest ;;
        amass) ensure_go && CGO_ENABLED=0 go install -v github.com/owasp-amass/amass/v5/cmd/amass@latest ;;
        httpx) ensure_go && go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest ;;
        katana) ensure_go && go install -v github.com/projectdiscovery/katana/cmd/katana@latest ;;
        gau) ensure_go && go install -v github.com/lc/gau/v2/cmd/gau@latest ;;
        waybackurls) ensure_go && go install -v github.com/tomnomnom/waybackurls@latest ;;
        hakrawler) ensure_go && go install -v github.com/hakluke/hakrawler@latest ;;
        nuclei) ensure_go && go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest ;;
        kxss) ensure_go && go install -v github.com/Emoe/kxss@latest ;;
        dalfox)
            case "$pm" in
                brew) install_packages brew dalfox && return $? ;;
                apt) install_packages apt dalfox && return $? ;;
                pacman) install_packages pacman dalfox && return $? ;;
                dnf) install_packages dnf dalfox && return $? ;;
            esac
            ensure_cargo && cargo install dalfox --locked
            ;;
        commix)
            ensure_git || return 1
            local root="${XDG_DATA_HOME:-$HOME/.local/share}/beltu-agent"
            local dir="$root/commix"
            ensure_dir "$root" || return 1
            if [[ -d "$dir/.git" ]]; then
                git -C "$dir" pull --ff-only || return 1
            else
                git clone --depth 1 https://github.com/commixproject/commix.git "$dir" || return 1
            fi
            ensure_dir "$HOME/.local/bin" || return 1
            cat > "$HOME/.local/bin/commix" <<EOF_COMMIX
#!/usr/bin/env bash
exec python3 "$dir/commix.py" "\$@"
EOF_COMMIX
            chmod 0755 "$HOME/.local/bin/commix" || return 1
            export PATH="$HOME/.local/bin:$PATH"
            ;;
        jq|pandoc) install_packages "$pm" "$tool" ;;
        weasyprint) install_weasyprint "$pm" ;;
        *) err "No installer implemented for '$tool'."; return 1 ;;
    esac
}

tool_probe_output() {
    local tool="$1" out="" help_out=""
    case "$tool" in
        assetfinder|waybackurls|hakrawler|kxss|gau)
            out="$("$tool" -h 2>&1 || true)"
            ;;
        subfinder|amass|httpx|katana|nuclei)
            out="$("$tool" -version 2>&1 || true)"
            help_out="$("$tool" -h 2>&1 || true)"
            [[ -n "$help_out" ]] && out="${out}"$'\n'"${help_out}"
            ;;
        dalfox|commix|jq|pandoc|weasyprint)
            out="$("$tool" --version 2>&1 || true)"
            [[ -z "$out" ]] && out="$("$tool" --help 2>&1 || true)"
            ;;
        *) out="" ;;
    esac
    printf '%s' "$out"
}

tool_version_output() {
    local tool="$1" out=""
    case "$tool" in
        assetfinder|waybackurls|hakrawler|kxss) out="$("$tool" -h 2>&1 || true)" ;;
        gau) out="$("$tool" --version 2>&1 || true)"; [[ -z "$out" ]] && out="$("$tool" -h 2>&1 || true)" ;;
        subfinder|amass|httpx|katana|nuclei) out="$("$tool" -version 2>&1 || true)" ;;
        dalfox|commix|jq|pandoc|weasyprint) out="$("$tool" --version 2>&1 || true)" ;;
        *) out="" ;;
    esac
    [[ -n "$out" ]] && printf '%s\n' "$out" | sed -n '1p'
}

tool_identity_ok() {
    local tool="$1" output lower
    output="$(tool_probe_output "$tool")"
    lower="${output,,}"
    case "$tool" in
        subfinder) [[ "$lower" == *subfinder* && ( "$lower" == *projectdiscovery* || "$lower" == *"-d"* ) ]] ;;
        httpx) [[ "$lower" == *httpx* && ( "$lower" == *projectdiscovery* || ( "$lower" == *"-status-code"* && "$lower" == *"-json"* ) ) ]] ;;
        nuclei) [[ "$lower" == *nuclei* && ( "$lower" == *projectdiscovery* || ( "$lower" == *"-jsonl"* && "$lower" == *template* ) ) ]] ;;
        katana) [[ "$lower" == *katana* && ( "$lower" == *projectdiscovery* || ( "$lower" == *concurrency* && "$lower" == *"-depth"* ) ) ]] ;;
        amass) [[ "$lower" == *amass* ]] ;;
        assetfinder) [[ "$lower" == *assetfinder* ]] ;;
        gau) [[ "$lower" == *gau* || "$lower" == *getallurls* ]] ;;
        waybackurls) [[ "$lower" == *waybackurls* || "$lower" == *usage* ]] ;;
        hakrawler) [[ "$lower" == *hakrawler* || "$lower" == *usage* ]] ;;
        dalfox) [[ "$lower" == *dalfox* ]] ;;
        kxss) [[ "$lower" == *kxss* || "$lower" == *usage* ]] ;;
        commix) [[ "$lower" == *commix* ]] ;;
        jq) [[ "$lower" == jq* ]] ;;
        pandoc) [[ "$lower" == pandoc* ]] ;;
        weasyprint) [[ "$lower" == *weasyprint* ]] ;;
        *) return 1 ;;
    esac
}

tool_compatibility_ok() {
    local tool="$1" help_text
    case "$tool" in
        subfinder) help_text="$("$tool" -h 2>&1 || true)"; [[ "$help_text" == *"-d"* && "$help_text" == *"-o"* && "$help_text" == *"-timeout"* && "$help_text" == *"-max-time"* ]] ;;
        assetfinder) help_text="$("$tool" -h 2>&1 || true)"; [[ "$help_text" == *"--subs-only"* ]] ;;
        amass) help_text="$("$tool" enum -h 2>&1 || true)"; [[ "$help_text" == *"-passive"* && "$help_text" == *"-d"* && "$help_text" == *"-o"* && "$help_text" == *"-timeout"* ]] ;;
        httpx) help_text="$("$tool" -h 2>&1 || true)"; [[ "$help_text" == *"-l"* && "$help_text" == *"-o"* && ( "$help_text" == *"-json"* || "$help_text" == *"-j,"* ) && "$help_text" == *"-t"* && "$help_text" == *"-rl"* && "$help_text" == *"-timeout"* && "$help_text" == *"-retries"* ]] ;;
        katana) help_text="$("$tool" -h 2>&1 || true)"; [[ "$help_text" == *"-list"* && "$help_text" == *"-o"* && "$help_text" == *"-cs"* && "$help_text" == *"-c"* && "$help_text" == *"-rl"* && "$help_text" == *"-timeout"* && "$help_text" == *"-retry"* ]] ;;
        gau) help_text="$("$tool" -h 2>&1 || true)"; [[ "$help_text" == *"--o"* && "$help_text" == *"--threads"* && "$help_text" == *"--timeout"* && "$help_text" == *"--retries"* && "$help_text" == *"--subs"* ]] ;;
        waybackurls) help_text="$("$tool" -h 2>&1 || true)"; [[ -n "$help_text" ]] ;;
        hakrawler) help_text="$("$tool" -h 2>&1 || true)"; [[ "$help_text" == *"-d"* && "$help_text" == *"-timeout"* ]] ;;
        nuclei) help_text="$("$tool" -h 2>&1 || true)"; [[ "$help_text" == *"-l"* && "$help_text" == *"-o"* && ( "$help_text" == *"-jsonl"* || "$help_text" == *"-j,"* ) && "$help_text" == *"-c"* && "$help_text" == *"-rl"* && "$help_text" == *"-timeout"* && "$help_text" == *"-retries"* ]] ;;
        dalfox) help_text="$("$tool" scan --help 2>&1 || "$tool" -h 2>&1 || true)"; [[ "$help_text" == *"file"* && "$help_text" == *"-o"* && "$help_text" == *"rate-limit"* && "$help_text" == *"timeout"* ]] ;;
        kxss) help_text="$("$tool" -h 2>&1 || true)"; [[ -n "$help_text" ]] ;;
        commix) help_text="$("$tool" --help 2>&1 || true)"; [[ "$help_text" == *"--batch"* && "$help_text" == *"--timeout"* && "$help_text" == *"-u"* ]] ;;
        jq|pandoc|weasyprint) return 0 ;;
        *) return 1 ;;
    esac
}

validate_tool() {
    local tool="$1" path version
    path="$(command -v "$tool" 2>/dev/null || true)"
    [[ -n "$path" && -x "$path" ]] || return 1
    tool_identity_ok "$tool" || return 1
    tool_compatibility_ok "$tool" || return 1
    version="$(tool_version_output "$tool")"
    ok "$tool detected"
    if [[ -n "$version" ]]; then printf '    Version: %s\n' "$version"; else printf '    Version: unavailable\n'; fi
}

build_required_tools() {
    REQUIRED_TOOLS=()
    local -a list=() tool
    (( MODE_DEEP == 1 || MODE_FULL == 1 )) && list+=(subfinder assetfinder amass httpx)
    (( MODE_URL == 1 || MODE_FULL == 1 )) && list+=(katana gau waybackurls hakrawler)
    (( MODE_VULN == 1 || MODE_FULL == 1 )) && list+=(nuclei kxss dalfox commix)
    (( MODE_FULL == 1 || MODE_REPORT_REQUESTED == 1 )) && list+=(jq pandoc weasyprint)
    for tool in "${list[@]}"; do
        local duplicate=0 existing
        for existing in "${REQUIRED_TOOLS[@]:-}"; do
            [[ "$existing" == "$tool" ]] && duplicate=1 && break
        done
        (( duplicate == 0 )) && REQUIRED_TOOLS+=("$tool")
    done
}

collect_dependency_status() {
    TOOL_OK=(); TOOL_BAD=(); TOOL_MISSING=()
    local tool
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if validate_tool "$tool" >/dev/null 2>&1; then
            TOOL_OK+=("$tool")
        elif command -v "$tool" >/dev/null 2>&1; then
            TOOL_BAD+=("$tool")
        else
            TOOL_MISSING+=("$tool")
        fi
    done
}

check_dependencies() {
    hdr "Dependency Check"
    build_required_tools
    collect_dependency_status

    local tool
    for tool in "${TOOL_BAD[@]}"; do warn "$tool found but validation failed"; done
    for tool in "${TOOL_MISSING[@]}"; do warn "$tool missing"; done

    if (( ${#TOOL_BAD[@]} == 0 && ${#TOOL_MISSING[@]} == 0 )); then
        ok "All dependencies required by selected mode(s) are valid."
        return 0
    fi

    printf '\n%bMissing/invalid dependencies:%b\n' "$C_YLW" "$C_RST"
    for tool in "${TOOL_MISSING[@]}" "${TOOL_BAD[@]}"; do [[ -n "$tool" ]] && printf '  - %s\n' "$tool"; done

    if (( NO_INSTALL == 1 )); then
        warn "Installation disabled (--no-install). Affected modules will be skipped."
    elif (( INSTALL_REQUESTED == 1 )); then
        for tool in "${TOOL_MISSING[@]}" "${TOOL_BAD[@]}"; do
            [[ -z "$tool" ]] && continue
            install_tool "$tool" || warn "Installation failed: $tool"
        done
        hash -r
    elif [[ -t 0 ]]; then
        local reply
        read -r -p "Install missing/invalid dependencies now? [Y/n] " reply || reply="n"
        reply="${reply:-Y}"
        if [[ "$reply" =~ ^[Yy]$ ]]; then
            for tool in "${TOOL_MISSING[@]}" "${TOOL_BAD[@]}"; do
                [[ -z "$tool" ]] && continue
                install_tool "$tool" || warn "Installation failed: $tool"
            done
            hash -r
        else
            warn "Installation declined."
        fi
    else
        warn "Non-interactive session: refusing unattended installation. Use --install explicitly."
    fi

    collect_dependency_status
    if (( ${#TOOL_BAD[@]} == 0 && ${#TOOL_MISSING[@]} == 0 )); then
        ok "Dependency installation/validation completed."
        return 0
    fi
    for tool in "${TOOL_BAD[@]}" "${TOOL_MISSING[@]}"; do [[ -n "$tool" ]] && warn "Unavailable: $tool"; done
    return 1
}

require_tool() {
    local tool="$1"
    validate_tool "$tool" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# Tool execution / structured logs
# -----------------------------------------------------------------------------
log_command_array() {
    local log_file="$1"; shift
    local item
    printf '%s ' "$(utc_iso)" >> "$log_file"
    for item in "$@"; do printf '%q ' "$item" >> "$log_file"; done
    printf '\n' >> "$log_file"
}

run_tool_stdout() {
    # Usage: run_tool_stdout MODULE TOOL RESULT_FILE INPUT_COUNT [ARGS...]
    local module="$1" tool="$2" result_file="$3" input_count="$4"; shift 4
    local start end rc duration log_file stdout_log stderr_log
    local -a cmd=("$tool" "$@")
    start="$(date +%s)"
    log_file="$TOOL_LOG_ROOT/${module}_${tool}.log"
    stdout_log="$TOOL_LOG_ROOT/${module}_${tool}.stdout.log"
    stderr_log="$TOOL_LOG_ROOT/${module}_${tool}.stderr.log"
    : > "$result_file"; : > "$stdout_log"; : > "$stderr_log"
    log_command_array "$log_file" "${cmd[@]}"
    printf 'tool=%s\nresult=%s\nstderr=%s\ninput_count=%s\n' "$tool" "$result_file" "$stderr_log" "$input_count" >> "$log_file"
    log "Running $tool"

    if (( DRY_RUN == 1 )); then
        printf 'DRY-RUN: %q ' "${cmd[@]}" > "$stdout_log"
        printf '\n' >> "$stdout_log"
        rc=0
    else
        if "${cmd[@]}" >"$result_file" 2>"$stderr_log"; then rc=0; else rc=$?; fi
    fi

    end="$(date +%s)"
    duration="$(elapsed_seconds "$start" "$end")"
    printf 'start_epoch=%s\nend_epoch=%s\nduration_seconds=%s\nexit_code=%s\n' "$start" "$end" "$duration" "$rc" >> "$log_file"
    if (( rc == 0 )); then ok "$tool completed in ${duration}s"; else warn "$tool failed (exit code $rc)"; fi
    return "$rc"
}

run_tool_output_arg() {
    # Usage: run_tool_output_arg MODULE TOOL RESULT_FILE INPUT_COUNT [ARGS...]
    # The wrapper appends -o RESULT_FILE to the command. Because the tool owns
    # the result file, stdout is redirected only to stdout_log and never to the
    # same path as RESULT_FILE.
    local module="$1" tool="$2" result_file="$3" input_count="$4"; shift 4
    local start end rc duration log_file stdout_log stderr_log
    local -a cmd=("$tool" "$@" -o "$result_file")
    start="$(date +%s)"
    log_file="$TOOL_LOG_ROOT/${module}_${tool}.log"
    stdout_log="$TOOL_LOG_ROOT/${module}_${tool}.stdout.log"
    stderr_log="$TOOL_LOG_ROOT/${module}_${tool}.stderr.log"
    : > "$result_file"; : > "$stdout_log"; : > "$stderr_log"
    log_command_array "$log_file" "${cmd[@]}"
    printf 'tool=%s\nresult=%s\nstdout=%s\nstderr=%s\ninput_count=%s\n' "$tool" "$result_file" "$stdout_log" "$stderr_log" "$input_count" >> "$log_file"
    log "Running $tool"

    if (( DRY_RUN == 1 )); then
        printf 'DRY-RUN: ' >> "$stdout_log"
        printf '%q ' "${cmd[@]}" >> "$stdout_log"
        printf '\n' >> "$stdout_log"
        rc=0
    else
        # IMPORTANT: result_file is written by the tool via its -o option.
        if "${cmd[@]}" >"$stdout_log" 2>"$stderr_log"; then rc=0; else rc=$?; fi
    fi

    end="$(date +%s)"; duration="$(elapsed_seconds "$start" "$end")"
    printf 'start_epoch=%s\nend_epoch=%s\nduration_seconds=%s\nexit_code=%s\n' "$start" "$end" "$duration" "$rc" >> "$log_file"
    if (( rc == 0 )); then ok "$tool completed in ${duration}s"; else warn "$tool failed (exit code $rc)"; fi
    return "$rc"
}

run_tool_named_output() {
    # Usage: run_tool_named_output MODULE TOOL RESULT_FILE INPUT_COUNT OUTPUT_FLAG [ARGS...]
    local module="$1" tool="$2" result_file="$3" input_count="$4" output_flag="$5"; shift 5
    local start end rc duration log_file stdout_log stderr_log
    local -a cmd=("$tool" "$@" "$output_flag" "$result_file")
    start="$(date +%s)"
    log_file="$TOOL_LOG_ROOT/${module}_${tool}.log"
    stdout_log="$TOOL_LOG_ROOT/${module}_${tool}.stdout.log"
    stderr_log="$TOOL_LOG_ROOT/${module}_${tool}.stderr.log"
    : > "$result_file"; : > "$stdout_log"; : > "$stderr_log"
    log_command_array "$log_file" "${cmd[@]}"
    printf 'tool=%s\nresult=%s\nstderr=%s\ninput_count=%s\n' "$tool" "$result_file" "$stderr_log" "$input_count" >> "$log_file"
    log "Running $tool"

    if (( DRY_RUN == 1 )); then
        printf 'DRY-RUN: ' >> "$stdout_log"; printf '%q ' "${cmd[@]}" >> "$stdout_log"; printf '\n' >> "$stdout_log"
        rc=0
    else
        if "${cmd[@]}" >"$stdout_log" 2>"$stderr_log"; then rc=0; else rc=$?; fi
    fi

    end="$(date +%s)"; duration="$(elapsed_seconds "$start" "$end")"
    printf 'start_epoch=%s\nend_epoch=%s\nduration_seconds=%s\nexit_code=%s\n' "$start" "$end" "$duration" "$rc" >> "$log_file"
    if (( rc == 0 )); then ok "$tool completed in ${duration}s"; else warn "$tool failed (exit code $rc)"; fi
    return "$rc"
}

run_tool_stdin() {
    # Usage: run_tool_stdin MODULE TOOL INPUT_FILE RESULT_FILE INPUT_COUNT [ARGS...]
    local module="$1" tool="$2" input_file="$3" result_file="$4" input_count="$5"; shift 5
    local start end rc duration log_file stdout_log stderr_log
    local -a cmd=("$tool" "$@")
    start="$(date +%s)"
    log_file="$TOOL_LOG_ROOT/${module}_${tool}.log"
    stdout_log="$TOOL_LOG_ROOT/${module}_${tool}.stdout.log"
    stderr_log="$TOOL_LOG_ROOT/${module}_${tool}.stderr.log"
    : > "$result_file"; : > "$stdout_log"; : > "$stderr_log"
    log_command_array "$log_file" "${cmd[@]}"
    printf 'tool=%s\ninput=%s\nresult=%s\nstderr=%s\ninput_count=%s\n' "$tool" "$input_file" "$result_file" "$stderr_log" "$input_count" >> "$log_file"
    log "Running $tool"

    if (( DRY_RUN == 1 )); then
        printf 'DRY-RUN: ' >> "$stdout_log"; printf '%q ' "${cmd[@]}" >> "$stdout_log"; printf '< %q\n' "$input_file" >> "$stdout_log"
        rc=0
    else
        if "${cmd[@]}" <"$input_file" >"$result_file" 2>"$stderr_log"; then rc=0; else rc=$?; fi
    fi

    end="$(date +%s)"; duration="$(elapsed_seconds "$start" "$end")"
    printf 'start_epoch=%s\nend_epoch=%s\nduration_seconds=%s\nexit_code=%s\n' "$start" "$end" "$duration" "$rc" >> "$log_file"
    if (( rc == 0 )); then ok "$tool completed in ${duration}s"; else warn "$tool failed (exit code $rc)"; fi
    return "$rc"
}

# -----------------------------------------------------------------------------
# URL processing
# -----------------------------------------------------------------------------
normalize_one_url() {
    local url="$1" rest authority suffix scheme hostpart userinfo hostport host port
    url="${url%%#*}"
    case "$url" in http://*|https://*) ;; *) return 1 ;; esac

    scheme="${url%%://*}"
    rest="${url#*://}"
    authority="${rest%%[/?]*}"
    [[ "$authority" == "$rest" ]] && suffix="" || suffix="${rest#"$authority"}"

    userinfo=""
    hostpart="$authority"
    if [[ "$hostpart" == *@* ]]; then
        userinfo="${hostpart%@*}@"
        hostpart="${hostpart##*@}"
    fi

    if [[ "$hostpart" == \[*\]:* ]]; then
        # Keep bracketed IPv6 authorities intact; scope checks remain hostname-oriented.
        hostport="$hostpart"
    elif [[ "$hostpart" == *:* ]]; then
        host="${hostpart%%:*}"
        port="${hostpart##*:}"
        if [[ "$scheme" == https && "$port" == 443 ]] || [[ "$scheme" == http && "$port" == 80 ]]; then
            hostport="$host"
        else
            hostport="$hostpart"
        fi
    else
        host="$hostpart"
        hostport="$host"
    fi
    hostpart="${hostport,,}"
    scheme="${scheme,,}"

    if [[ -z "$suffix" ]]; then
        suffix="/"
    elif [[ "$suffix" == \?* ]]; then
        suffix="/$suffix"
    fi
    printf '%s://%s%s%s\n' "$scheme" "$userinfo" "$hostpart" "$suffix"
}

scope_domain_regex() {
    local domain="$1"
    domain=${domain//./\\.}
    printf '%s' "$domain"
}

build_katana_scope_file() {
    local output="$1" line pattern domain escaped
    : > "$output" || return 1
    [[ -n "$SCOPE_FILE" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        pattern="$(trim_ws "${line%%#*}")"
        [[ -z "$pattern" ]] && continue
        if [[ "$pattern" == \*.* ]]; then
            domain="${pattern#*.}"
            escaped="$(scope_domain_regex "$domain")"
            # One or more labels before the scoped suffix => wildcard does not include apex.
            printf '^https?://([A-Za-z0-9-]+\\.)+%s(?::[0-9]+)?(?:[/#?]|$)' "$escaped" >> "$output"
        else
            escaped="$(scope_domain_regex "$pattern")"
            printf '^https?://%s(?::[0-9]+)?(?:[/#?]|$)' "$escaped" >> "$output"
        fi
        printf '\n' >> "$output"
    done < "$SCOPE_FILE"
}

filter_in_scope_url_list() {
    local input="$1" output="$2" line host
    : > "$output"
    while IFS= read -r line || [[ -n "$line" ]]; do
        host="$(host_from_url "$(trim_ws "$line")")"
        [[ -n "$host" ]] || continue
        is_in_scope "$host" && printf '%s\n' "$(trim_ws "$line")" >> "$output"
    done < "$input"
    sort -u "$output" -o "$output"
}

filter_scope_subdomains() {
    local input="$1" output="$2" line host
    : > "$output"
    while IFS= read -r line || [[ -n "$line" ]]; do
        host="$(trim_ws "$line")"
        [[ -z "$host" ]] && continue
        if is_in_scope "$host"; then printf '%s\n' "${host,,}" >> "$output"; fi
    done < "$input"
    sort -u "$output" -o "$output"
}

normalize_urls() {
    local input="$1" output="$2" line cleaned host normalized
    : > "$output"
    while IFS= read -r line || [[ -n "$line" ]]; do
        cleaned="$(trim_ws "$line")"
        [[ -z "$cleaned" ]] && continue
        normalized="$(normalize_one_url "$cleaned" 2>/dev/null || true)"
        [[ -z "$normalized" ]] && continue
        if [[ -n "$SCOPE_FILE" ]]; then
            host="$(host_from_url "$normalized")"
            [[ -n "$host" ]] || continue
            is_in_scope "$host" || continue
        fi
        printf '%s\n' "$normalized" >> "$output"
    done < "$input"
    sort -u "$output" -o "$output"
}

extract_url_data() {
    local all_urls="$1" url_dir="$2"
    local params="$url_dir/urls_with_params.txt"
    local endpoints="$url_dir/unique_endpoints.txt"
    local unique_params="$url_dir/unique_parameters.txt"
    local parameterized_endpoints="$url_dir/parameterized_endpoints.txt"

    : > "$params"; : > "$endpoints"; : > "$unique_params"; : > "$parameterized_endpoints"

    awk 'index($0,"?")==0 {next} {q=substr($0,index($0,"?")+1); n=split(q,a,"&"); ok=0; for(i=1;i<=n;i++){if(index(a[i],"=")>1){ok=1; break}} if(ok) print $0}' "$all_urls" | sort -u > "$params"
    sed 's/[?#].*$//' "$all_urls" | sed '/^$/d' | sort -u > "$endpoints"
    awk -F'?' '{if(NF<2) next; n=split($2,a,"&"); for(i=1;i<=n;i++){p=index(a[i],"="); if(p>1) print substr(a[i],1,p-1)}}' "$params" | sed '/^$/d' | sort -u > "$unique_params"
    sed 's/[?#].*$//' "$params" | sed '/^$/d' | sort -u > "$parameterized_endpoints"
}

# -----------------------------------------------------------------------------
# Modules
# -----------------------------------------------------------------------------
tool_timeout_minutes() {
    local seconds="$1" minutes
    minutes=$(( (seconds + 59) / 60 ))
    (( minutes < 1 )) && minutes=1
    printf '%s' "$minutes"
}

module_deep_enum() {
    local module="deep_enum" start end rc=0 failures=0
    local out_dir="$OUTDIR/subdomains" all_subs="$OUTDIR/subdomains/all_subdomains.txt"
    local scoped_subs="$OUTDIR/subdomains/scoped_subdomains.txt" seed_file="$TMP_DIR/deep_seed.txt"
    local count live_count enum_minutes
    local enum_successes=0 enum_failures=0 probe_successes=0 probe_failures=0 total_successes=0 total_failures=0

    : > "$out_dir/subfinder.txt"; : > "$out_dir/assetfinder.txt"; : > "$out_dir/amass.txt"
    : > "$out_dir/all_subdomains.txt"; : > "$out_dir/scoped_subdomains.txt"
    : > "$out_dir/live_hosts.txt"; : > "$out_dir/httpx_results.jsonl"
    printf '%s\n' "$TARGET" > "$seed_file"

    start="$(date +%s)"; DEEP_STATUS="running"; write_state "$module" running "$start" 0 0 "" || return 1
    hdr "Deep Subdomain Enumeration & Active Host Probing"
    enum_minutes="$(tool_timeout_minutes "$TIMEOUT")"

    if require_tool subfinder; then
        if run_tool_output_arg "$module" subfinder "$out_dir/subfinder.txt" 1 -d "$TARGET" -all -silent -timeout "$TIMEOUT" -max-time "$enum_minutes"; then enum_successes=$((enum_successes + 1)); else enum_failures=$((enum_failures + 1)); fi
    else warn "Skipping subfinder: unavailable."; enum_failures=$((enum_failures + 1)); fi

    if require_tool assetfinder; then
        if run_tool_stdout "$module" assetfinder "$out_dir/assetfinder.txt" 1 --subs-only "$TARGET"; then enum_successes=$((enum_successes + 1)); else enum_failures=$((enum_failures + 1)); fi
    else warn "Skipping assetfinder: unavailable."; enum_failures=$((enum_failures + 1)); fi

    if require_tool amass; then
        if run_tool_output_arg "$module" amass "$out_dir/amass.txt" 1 enum -passive -d "$TARGET" -timeout "$enum_minutes"; then enum_successes=$((enum_successes + 1)); else enum_failures=$((enum_failures + 1)); fi
    else warn "Skipping amass: unavailable."; enum_failures=$((enum_failures + 1)); fi

    cat "$seed_file" "$out_dir/subfinder.txt" "$out_dir/assetfinder.txt" "$out_dir/amass.txt" 2>/dev/null \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
        | grep -E '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$' \
        | tr '[:upper:]' '[:lower:]' | sort -u > "$all_subs" || :

    count="$(count_lines "$all_subs")"; ok "Unique subdomains/seed hosts: $count"
    filter_scope_subdomains "$all_subs" "$scoped_subs"
    [[ -n "$SCOPE_FILE" ]] && ok "In-scope hosts: $(count_lines "$scoped_subs")"

    if require_tool httpx; then
        local input_count
        input_count="$(count_lines "$scoped_subs")"
        local -a args=(-l "$scoped_subs" -silent -status-code -title -tech-detect -json -t "$THREADS" -rl "$RATE_LIMIT" -timeout "$TIMEOUT" -retries "$RETRIES")
        if run_tool_output_arg "$module" httpx "$out_dir/httpx_results.jsonl" "$input_count" "${args[@]}"; then probe_successes=$((probe_successes + 1)); else probe_failures=$((probe_failures + 1)); fi
        if [[ -s "$out_dir/httpx_results.jsonl" ]]; then
            if command -v jq >/dev/null 2>&1 && jq -e . >/dev/null 2>&1 < "$out_dir/httpx_results.jsonl"; then
                jq -r 'select(type=="object") | (.url // .input // empty)' "$out_dir/httpx_results.jsonl" 2>/dev/null | sed '/^$/d' | sort -u > "$out_dir/live_hosts.txt" || :
            fi
            if [[ ! -s "$out_dir/live_hosts.txt" ]]; then
                grep -Eo 'https?://[^"[:space:],}]+' "$out_dir/httpx_results.jsonl" 2>/dev/null | sort -u > "$out_dir/live_hosts.txt" || :
            fi
        fi
        live_count="$(count_lines "$out_dir/live_hosts.txt")"; ok "Live hosts: $live_count"
    else warn "Skipping httpx: unavailable."; probe_failures=$((probe_failures + 1)); fi

    total_successes=$((enum_successes + probe_successes))
    total_failures=$((enum_failures + probe_failures))
    end="$(date +%s)"
    if (( total_failures == 0 )); then DEEP_STATUS="completed"; rc=0
    elif (( total_successes > 0 )); then DEEP_STATUS="partial"; rc=1
    else DEEP_STATUS="failed"; rc=1; fi
    write_state "$module" "$DEEP_STATUS" "$start" "$end" "$rc" "enumeration_successes=$enum_successes enumeration_failures=$enum_failures probe_successes=$probe_successes probe_failures=$probe_failures"
    (( rc == 0 ))
}

module_url_crawl() {
    local module="url_crawl" start end rc=0 failures=0
    local url_dir="$OUTDIR/urls" live_hosts="$OUTDIR/subdomains/live_hosts.txt"
    local crawl_input="$TMP_DIR/crawl_input.txt" seed_file="$TMP_DIR/seed_target.txt" all_raw="$TMP_DIR/all_urls.raw"
    local url_count param_count

    : > "$all_raw"
    : > "$url_dir/katana.txt"; : > "$url_dir/gau.txt"; : > "$url_dir/waybackurls.txt"; : > "$url_dir/hakrawler.txt"
    : > "$url_dir/all_urls.txt"; : > "$url_dir/urls_with_params.txt"; : > "$url_dir/unique_endpoints.txt"
    : > "$url_dir/unique_parameters.txt"; : > "$url_dir/parameterized_endpoints.txt"
    printf '%s\n' "$TARGET" > "$seed_file"

    start="$(date +%s)"; URL_STATUS="running"; write_state "$module" running "$start" 0 0 "" || return 1
    hdr "URL Crawling & Parameter Mining"

    if [[ -s "$live_hosts" ]]; then
        if [[ -n "$SCOPE_FILE" ]]; then
            filter_in_scope_url_list "$live_hosts" "$crawl_input"
        else
            cp -- "$live_hosts" "$crawl_input"
        fi
    else
        printf 'https://%s\n' "$TARGET" > "$crawl_input"
        warn "No live-host file available; falling back to https://$TARGET"
    fi
    if [[ -n "$SCOPE_FILE" && ! -s "$crawl_input" ]]; then
        err "No in-scope crawl seeds are available."
        URL_STATUS="failed"
        end="$(date +%s)"
        write_state "$module" "$URL_STATUS" "$start" "$end" 1 "no_in_scope_crawl_seeds"
        return 1
    fi
    local crawl_count="$(count_lines "$crawl_input")"

    if require_tool katana; then
        local katana_scope_file="$TMP_DIR/katana_scope.regex"
        [[ -n "$SCOPE_FILE" ]] && build_katana_scope_file "$katana_scope_file"
        local -a args=(-list "$crawl_input" -silent -jc -kf all -c "$THREADS" -p 1 -rl "$RATE_LIMIT" -timeout "$TIMEOUT" -retry "$RETRIES")
        if [[ -n "$SCOPE_FILE" ]]; then
            args+=(-cs "$katana_scope_file")
        fi
        if run_tool_output_arg "$module" katana "$url_dir/katana.txt" "$crawl_count" "${args[@]}"; then cat "$url_dir/katana.txt" >> "$all_raw"; else failures=$((failures + 1)); fi
    else warn "Skipping katana: unavailable."; failures=$((failures + 1)); fi

    if require_tool gau; then
        local -a args=(--subs --threads "$THREADS" --timeout "$TIMEOUT" --retries "$RETRIES" "$TARGET")
        if run_tool_named_output "$module" gau "$url_dir/gau.txt" 1 --o "${args[@]}"; then cat "$url_dir/gau.txt" >> "$all_raw"; else failures=$((failures + 1)); fi
    else warn "Skipping gau: unavailable."; failures=$((failures + 1)); fi

    if require_tool waybackurls; then
        if run_tool_stdin "$module" waybackurls "$seed_file" "$url_dir/waybackurls.txt" 1; then cat "$url_dir/waybackurls.txt" >> "$all_raw"; else failures=$((failures + 1)); fi
    else warn "Skipping waybackurls: unavailable."; failures=$((failures + 1)); fi

    if require_tool hakrawler; then
        if run_tool_stdin "$module" hakrawler "$crawl_input" "$url_dir/hakrawler.txt" "$crawl_count" -d 2 -t "$THREADS" -timeout "$TIMEOUT"; then cat "$url_dir/hakrawler.txt" >> "$all_raw"; else failures=$((failures + 1)); fi
    else warn "Skipping hakrawler: unavailable."; failures=$((failures + 1)); fi

    normalize_urls "$all_raw" "$url_dir/all_urls.txt"
    extract_url_data "$url_dir/all_urls.txt" "$url_dir"
    url_count="$(count_lines "$url_dir/all_urls.txt")"; param_count="$(count_lines "$url_dir/urls_with_params.txt")"
    ok "Unique URLs: $url_count"; ok "Parameterized URLs: $param_count"; ok "Unique endpoints: $(count_lines "$url_dir/unique_endpoints.txt")"; ok "Unique parameters: $(count_lines "$url_dir/unique_parameters.txt")"

    end="$(date +%s)"
    if (( failures == 0 )); then URL_STATUS="completed"; rc=0
    elif (( url_count > 0 )); then URL_STATUS="partial"; rc=1
    else URL_STATUS="failed"; rc=1; fi
    write_state "$module" "$URL_STATUS" "$start" "$end" "$rc" "failures=$failures"
    (( rc == 0 ))
}

run_with_timeout_compat() {
    local seconds="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "${seconds}s" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "${seconds}s" "$@"
    else
        "$@"
    fi
}

run_commix_bounded() {
    local input="$1" output="$2" count=0 rc=0 start end duration url temp_out
    local tool_log="$TOOL_LOG_ROOT/vuln_scan_commix.log" stderr_log="$TOOL_LOG_ROOT/vuln_scan_commix.stderr.log"
    : > "$output"; : > "$tool_log"; : > "$stderr_log"
    start="$(date +%s)"

    while IFS= read -r url || [[ -n "$url" ]]; do
        [[ -z "$url" ]] && continue
        (( count >= MAX_INJECTION_TARGETS )) && break
        count=$((count + 1))
        temp_out="$TMP_DIR/commix_${count}.txt"
        local -a cmd=(commix --batch "--timeout=$TIMEOUT" -u "$url")
        log_command_array "$tool_log" "${cmd[@]}"
        if (( DRY_RUN == 1 )); then
            printf 'DRY-RUN target=%s\n' "$url" >> "$output"
            continue
        fi
        if run_with_timeout_compat "$TIMEOUT" "${cmd[@]}" >"$temp_out" 2>>"$stderr_log"; then
            cat "$temp_out" >> "$output" 2>/dev/null || :
        else
            rc=1
            printf 'TARGET: %s\n' "$url" >> "$output"
            cat "$temp_out" >> "$output" 2>/dev/null || :
            printf '\n' >> "$output"
        fi
    done < "$input"

    end="$(date +%s)"; duration="$(elapsed_seconds "$start" "$end")"
    printf 'start_epoch=%s\nend_epoch=%s\nduration_seconds=%s\ninput_count=%s\nmax_targets=%s\nexit_code=%s\n' "$start" "$end" "$duration" "$count" "$MAX_INJECTION_TARGETS" "$rc" >> "$tool_log"
    if (( rc == 0 )); then ok "commix bounded sample completed: $count target(s)"; else warn "commix completed with errors for one or more bounded targets"; fi
    (( rc == 0 ))
}

module_vuln_scan() {
    local module="vuln_scan" start end rc=0 failures=0
    local vuln_dir="$OUTDIR/vulnerabilities" live_hosts="$OUTDIR/subdomains/live_hosts.txt" param_urls="$OUTDIR/urls/urls_with_params.txt"
    local scan_targets="$TMP_DIR/vuln_targets.txt" nuclei_count

    : > "$vuln_dir/nuclei_results.jsonl"; : > "$vuln_dir/kxss_results.txt"; : > "$vuln_dir/dalfox_results.txt"; : > "$vuln_dir/commix_results.txt"
    printf 'https://%s\n' "$TARGET" > "$scan_targets"
    [[ -s "$live_hosts" ]] && cp -- "$live_hosts" "$scan_targets"

    if [[ -n "$SCOPE_FILE" ]]; then
        local scoped="$TMP_DIR/vuln_targets_scoped.txt" host url
        : > "$scoped"
        while IFS= read -r url || [[ -n "$url" ]]; do
            host="$(host_from_url "$url")"
            [[ -n "$host" ]] && is_in_scope "$host" && printf '%s\n' "$url" >> "$scoped"
        done < "$scan_targets"
        sort -u "$scoped" -o "$scoped"
        cp -- "$scoped" "$scan_targets"
    fi

    start="$(date +%s)"; VULN_STATUS="running"; write_state "$module" running "$start" 0 0 "" || return 1
    hdr "Vulnerability Scanning Suite"

    NUCLEI_STATUS="skipped"; KXSS_STATUS="skipped"; DALFOX_STATUS="skipped"; COMMIX_STATUS="skipped"

    if require_tool nuclei; then
        local -a args=(-l "$scan_targets" -silent -severity info,low,medium,high,critical -jsonl -c "$THREADS" -rl "$RATE_LIMIT" -timeout "$TIMEOUT" -retries "$RETRIES")
        if run_tool_output_arg "$module" nuclei "$vuln_dir/nuclei_results.jsonl" "$(count_lines "$scan_targets")" "${args[@]}"; then
            NUCLEI_STATUS="completed"; nuclei_count="$(count_lines "$vuln_dir/nuclei_results.jsonl")"; ok "nuclei potential findings: $nuclei_count"
        else
            NUCLEI_STATUS="failed"; failures=$((failures + 1)); nuclei_count=""
        fi
    else
        NUCLEI_STATUS="skipped"; warn "Skipping nuclei: unavailable."; failures=$((failures + 1))
    fi

    if [[ -s "$param_urls" ]]; then
        local param_count="$(count_lines "$param_urls")"
        if require_tool kxss; then
            if run_tool_stdin "$module" kxss "$param_urls" "$vuln_dir/kxss_results.txt" "$param_count"; then KXSS_STATUS="completed"; else KXSS_STATUS="failed"; failures=$((failures + 1)); fi
        else KXSS_STATUS="skipped"; warn "Skipping kxss: unavailable."; failures=$((failures + 1)); fi

        if require_tool dalfox; then
            local -a args=(scan file "$param_urls" --silence --no-color --rate-limit "$RATE_LIMIT" --timeout "$TIMEOUT")
            local dalfox_help="$(dalfox scan --help 2>&1 || true)"
            if [[ "$dalfox_help" == *"--workers"* ]]; then args+=(--workers "$THREADS"); elif [[ "$dalfox_help" == *"--concurrency"* ]]; then args+=(--concurrency "$THREADS"); fi
            if [[ "$dalfox_help" == *"--retries"* ]]; then args+=(--retries "$RETRIES"); fi
            if run_tool_output_arg "$module" dalfox "$vuln_dir/dalfox_results.txt" "$param_count" "${args[@]}"; then DALFOX_STATUS="completed"; else DALFOX_STATUS="failed"; failures=$((failures + 1)); fi
        else DALFOX_STATUS="skipped"; warn "Skipping dalfox: unavailable."; failures=$((failures + 1)); fi

        if require_tool commix; then
            if run_commix_bounded "$param_urls" "$vuln_dir/commix_results.txt"; then COMMIX_STATUS="completed"; else COMMIX_STATUS="failed"; failures=$((failures + 1)); fi
        else COMMIX_STATUS="skipped"; warn "Skipping commix: unavailable."; failures=$((failures + 1)); fi
    else
        KXSS_STATUS="skipped"; DALFOX_STATUS="skipped"; COMMIX_STATUS="skipped"
        ok "No parameterized URLs found; kxss/dalfox/commix skipped."
    fi

    end="$(date +%s)"
    if (( failures == 0 )); then VULN_STATUS="completed"; rc=0
    elif [[ -s "$vuln_dir/nuclei_results.jsonl" || -s "$vuln_dir/kxss_results.txt" || -s "$vuln_dir/dalfox_results.txt" || -s "$vuln_dir/commix_results.txt" ]]; then VULN_STATUS="partial"; rc=1
    else VULN_STATUS="failed"; rc=1; fi
    write_state "$module" "$VULN_STATUS" "$start" "$end" "$rc" "failures=$failures"
    (( rc == 0 ))
}

# -----------------------------------------------------------------------------
# Reporting
# -----------------------------------------------------------------------------
severity_count() {
    local severity="$1" file="$2"
    if ! command -v jq >/dev/null 2>&1 || [[ ! -s "$file" ]]; then printf 'NA'; return 0; fi
    jq -r --arg sev "$severity" 'select(type=="object") | (.info.severity // "unknown") | ascii_downcase | select(. == $sev)' "$file" 2>/dev/null | wc -l | tr -d '[:space:]'
}

report_tool_status() {
    local tool="$1" item
    for item in "${TOOL_OK[@]}"; do [[ "$item" == "$tool" ]] && { printf 'validated'; return; }; done
    for item in "${TOOL_BAD[@]}"; do [[ "$item" == "$tool" ]] && { printf 'found, validation failed'; return; }; done
    for item in "${TOOL_MISSING[@]}"; do [[ "$item" == "$tool" ]] && { printf 'missing'; return; }; done
    printf 'not required'
}

scanner_report_status() {
    local tool="$1"
    case "$tool" in
        nuclei) printf '%s' "$NUCLEI_STATUS" ;;
        kxss) printf '%s' "$KXSS_STATUS" ;;
        dalfox) printf '%s' "$DALFOX_STATUS" ;;
        commix) printf '%s' "$COMMIX_STATUS" ;;
        *) printf 'not_run' ;;
    esac
}

build_report_html() {
    command -v pandoc >/dev/null 2>&1 || return 1
    pandoc "$OUTDIR/report.md" -o "$OUTDIR/report.html" >"$TOOL_LOG_ROOT/report_pandoc.stdout.log" 2>"$TOOL_LOG_ROOT/report_pandoc.stderr.log"
}

generate_report() {
    local module="report" start end rc=0
    local report_md="$OUTDIR/report.md" report_pdf="$OUTDIR/report.pdf"
    local sub_count live_count url_count param_count endpoint_count unique_param_count
    local crit high medium low info nuclei_file overall_report_status

    start="$(date +%s)"; REPORT_STATUS="running"; write_state "$module" running "$start" 0 0 "" || return 1
    hdr "Compiling Security Assessment Report"

    sub_count="$(count_lines "$OUTDIR/subdomains/all_subdomains.txt")"
    live_count="$(count_lines "$OUTDIR/subdomains/live_hosts.txt")"
    url_count="$(count_lines "$OUTDIR/urls/all_urls.txt")"
    param_count="$(count_lines "$OUTDIR/urls/urls_with_params.txt")"
    endpoint_count="$(count_lines "$OUTDIR/urls/unique_endpoints.txt")"
    unique_param_count="$(count_lines "$OUTDIR/urls/unique_parameters.txt")"
    nuclei_file="$OUTDIR/vulnerabilities/nuclei_results.jsonl"
    crit="$(severity_count critical "$nuclei_file")"; high="$(severity_count high "$nuclei_file")"; medium="$(severity_count medium "$nuclei_file")"; low="$(severity_count low "$nuclei_file")"; info="$(severity_count info "$nuclei_file")"

    overall_report_status="completed"
    case "$DEEP_STATUS:$URL_STATUS:$VULN_STATUS" in *failed*|*partial*) overall_report_status="partial" ;; esac

    {
        printf '# BelTu-Agent Security Assessment Report\n\n'
        printf '**Target:** `%s`  \n' "$TARGET"
        printf '**Assessment Date:** %s  \n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        printf '**Tool:** %s v%s  \n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
        printf '**Mode:** %s  \n' "$(mode_label)"
        printf '**Overall Status:** %s\n\n' "$overall_report_status"
        printf '> **Authorized-use notice:** This report is for systems you own or are explicitly authorized to assess. Automated detections require manual verification.\n\n---\n\n'

        printf '## Executive Summary\n\n'
        printf '| Metric | Value |\n|---|---:|\n'
        printf '| Unique subdomains / seed hosts | %s |\n' "$sub_count"
        printf '| Live hosts | %s |\n' "$live_count"
        printf '| Unique URLs | %s |\n' "$url_count"
        printf '| Parameterized URLs | %s |\n' "$param_count"
        printf '| Unique endpoints | %s |\n' "$endpoint_count"
        printf '| Unique parameters | %s |\n\n' "$unique_param_count"

        printf '## Attack Surface\n\n'
        printf '| Artifact | Evidence | Count |\n|---|---|---:|\n'
        printf '| Subdomains | `subdomains/all_subdomains.txt` | %s |\n' "$sub_count"
        printf '| In-scope subdomains | `subdomains/scoped_subdomains.txt` | %s |\n' "$(count_lines "$OUTDIR/subdomains/scoped_subdomains.txt")"
        printf '| Live hosts | `subdomains/live_hosts.txt` | %s |\n' "$live_count"
        printf '| URLs | `urls/all_urls.txt` | %s |\n' "$url_count"
        printf '| Parameterized URLs | `urls/urls_with_params.txt` | %s |\n' "$param_count"
        printf '| Endpoints | `urls/unique_endpoints.txt` | %s |\n' "$endpoint_count"
        printf '| Parameters | `urls/unique_parameters.txt` | %s |\n\n' "$unique_param_count"

        printf '## Findings Summary\n\n'
        if [[ "$NUCLEI_STATUS" == failed ]]; then
            printf '**Nuclei:** Scanner failed. Severity counts are not interpreted as zero. See `logs/tools/vuln_scan_nuclei.stderr.log`.\n\n'
        elif [[ "$NUCLEI_STATUS" == skipped ]]; then
            printf '**Nuclei:** Scanner skipped/unavailable; no conclusion about zero findings is made.\n\n'
        elif [[ "$NUCLEI_STATUS" == completed ]]; then
            printf '| Severity | Automated detections |\n|---|---:|\n'
            printf '| Critical | %s |\n| High | %s |\n| Medium | %s |\n| Low | %s |\n| Informational | %s |\n\n' "$crit" "$high" "$medium" "$low" "$info"
        fi

        printf '## Scanner Results\n\n'
        printf '| Scanner | Status | Evidence |\n|---|---|---|\n'
        printf '| Nuclei | %s | `vulnerabilities/nuclei_results.jsonl` + `logs/tools/vuln_scan_nuclei.*` |\n' "$(scanner_report_status nuclei)"
        if [[ "$param_count" != 0 ]]; then
            printf '| kxss | %s | `vulnerabilities/kxss_results.txt` + tool logs |\n' "$(scanner_report_status kxss)"
            printf '| Dalfox | %s | `vulnerabilities/dalfox_results.txt` + tool logs |\n' "$(scanner_report_status dalfox)"
            printf '| commix | %s | `vulnerabilities/commix_results.txt` + tool logs |\n' "$(scanner_report_status commix)"
        else
            printf '| kxss | skipped: no parameterized URLs | `urls/urls_with_params.txt` |\n'
            printf '| Dalfox | skipped: no parameterized URLs | `urls/urls_with_params.txt` |\n'
            printf '| commix | skipped: no parameterized URLs | `urls/urls_with_params.txt` |\n'
        fi
        printf '\n'

        printf '## Tool Coverage\n\n'
        printf '| Tool | Dependency status | Run status where applicable |\n|---|---|---|\n'
        local tool
        for tool in subfinder assetfinder amass httpx katana gau waybackurls hakrawler nuclei kxss dalfox commix jq pandoc weasyprint; do
            printf '| %s | %s | %s |\n' "$tool" "$(report_tool_status "$tool")" "$(scanner_report_status "$tool")"
        done
        printf '\n'

        printf '## Module Status\n\n'
        printf '| Module | Status |\n|---|---|\n'
        printf '| Deep Subdomain Enumeration & Active Host Probing | %s |\n' "$DEEP_STATUS"
        printf '| URL Crawling & Parameter Mining | %s |\n' "$URL_STATUS"
        printf '| Vulnerability Scanning | %s |\n' "$VULN_STATUS"
        printf '| Reporting | %s |\n\n' "$REPORT_STATUS"

        printf '## Raw Evidence\n\n'
        printf '%s\n' \
            '- `metadata/target.txt`' \
            '- `metadata/config.txt`' \
            '- `metadata/state.tsv`' \
            '- `metadata/run.json`' \
            '- `subdomains/` raw enumeration and probing results' \
            '- `urls/` raw crawler/provider results and normalized URL data' \
            '- `vulnerabilities/` scanner outputs' \
            '- `logs/tools/` command, stdout, stderr, timing, and exit-code records'
        printf '\n'

        printf '## Verification Guidance\n\n'
        printf 'Automated detections are candidates for manual investigation. Verify scope, reproduce the behavior, establish security impact, and confirm the final severity before disclosure or remediation.\n\n'

        printf '## Disclaimer\n\n'
        printf 'BelTu-Agent does not guarantee complete coverage. Tool output can contain false positives, false negatives, stale historical data, or scanner errors. A zero-finding result is not proof that a target is secure.\n'
    } > "$report_md" || { REPORT_STATUS="failed"; write_state "$module" failed "$start" "$(date +%s)" 1 "report_write_failed"; return 1; }

    ok "Markdown report -> $report_md"

    if build_report_html; then
        ok "HTML report -> $OUTDIR/report.html"
        if command -v weasyprint >/dev/null 2>&1; then
            if weasyprint "$OUTDIR/report.html" "$report_pdf" >"$TOOL_LOG_ROOT/report_weasyprint.stdout.log" 2>"$TOOL_LOG_ROOT/report_weasyprint.stderr.log"; then
                ok "PDF report -> $report_pdf"
            else
                warn "WeasyPrint PDF generation failed; Markdown/HTML reports remain available."; rc=1
            fi
        else
            warn "WeasyPrint unavailable; PDF report not generated."; rc=1
        fi
    else
        warn "Pandoc HTML generation failed; see logs/tools/report_pandoc.stderr.log."; rc=1
    fi

    end="$(date +%s)"
    if (( rc == 0 )); then REPORT_STATUS="completed"; else REPORT_STATUS="partial"; fi

    # The Markdown file is written before PDF conversion so it can exist even
    # when a later report stage fails. Update the document with the final
    # reporting/overall status once the complete report pipeline is known.
    local final_overall="completed"
    case "$DEEP_STATUS:$URL_STATUS:$VULN_STATUS:$REPORT_STATUS" in
        *failed*|*partial*) final_overall="partial" ;;
    esac
    if [[ -f "$report_md" ]]; then
        sed -i "s/^\*\*Overall Status:\*\* .*/**Overall Status:** $final_overall/" "$report_md" 2>/dev/null || true
        sed -i "s/^| Reporting | .* |$/| Reporting | $REPORT_STATUS |/" "$report_md" 2>/dev/null || true
    fi

    write_state "$module" "$REPORT_STATUS" "$start" "$end" "$rc" ""
    (( rc == 0 ))
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    trap cleanup EXIT
    trap 'handle_signal SIGINT' INT
    trap 'handle_signal SIGTERM' TERM

    (($# > 0)) || { usage; return 1; }

    local -a normalized_args
    mapfile -t normalized_args < <(preprocess_short_clusters "$@")
    parse_args "${normalized_args[@]}" || { usage; return 1; }

    if [[ -n "$CONFIG_FILE" ]]; then
        load_config_file "$CONFIG_FILE" || return 1
    fi

    if (( DRY_RUN == 1 && INSTALL_REQUESTED == 1 )); then
        err "--dry-run cannot be combined with --install"
        return 1
    fi
    if (( INSTALL_REQUESTED == 1 && NO_INSTALL == 1 )); then
        err "--install and --no-install cannot be used together"
        return 1
    fi
    (( INSTALL_REQUESTED == 1 )) && NO_INSTALL=0

    if [[ -n "$RESUME_DIR" && $MODE_DEEP -eq 0 && $MODE_URL -eq 0 && $MODE_VULN -eq 0 && $MODE_FULL -eq 0 ]]; then
        MODE_FULL=1
        ok "Resume mode without an explicit stage: using full pipeline and skipping completed stages."
    fi

    validate_runtime_options || return 1

    MODE_REPORT_REQUESTED=$(( MODE_FULL ))
    if (( MODE_DEEP == 0 && MODE_URL == 0 && MODE_VULN == 0 && MODE_FULL == 0 )); then
        err "No mode selected. Use -d, -a, -v, or -f."
        usage
        return 1
    fi

    print_banner
    validate_core_commands || return 1

    if [[ -n "$RESUME_DIR" ]]; then
        if [[ -n "$TARGET_RAW" ]]; then
            local supplied resume_target
            supplied="$(sanitize_domain "$TARGET_RAW")" || return 1
            [[ -f "$RESUME_DIR/metadata/target.txt" ]] || { err "Resume metadata missing target.txt."; return 1; }
            resume_target="$(tr -d '\r\n' < "$RESUME_DIR/metadata/target.txt")"
            resume_target="$(sanitize_domain "$resume_target")" || return 1
            [[ "$supplied" == "$resume_target" ]] || { err "Resume target mismatch."; return 1; }
        fi
        load_resume_run || return 1
        init_temp || return 1
        validate_scope_file || return 1
        write_config_snapshot || return 1
    else
        [[ -n "$TARGET_RAW" ]] || { err "Target domain is required (-t <domain>)."; usage; return 1; }
        TARGET="$(sanitize_domain "$TARGET_RAW")" || return 1
        validate_scope_file || return 1
        init_temp || return 1
        setup_new_run || return 1
    fi

    if [[ -n "$SCOPE_FILE" ]]; then
        ok "Scope allowlist active: $SCOPE_FILE"
    else
        warn "No --scope file supplied. Run only against explicitly authorized targets and obey the program scope/rate limits."
    fi

    if (( DRY_RUN == 1 )); then
        # Dry-run must not execute dependency binaries or installers. It only
        # builds the plan from the already parsed configuration.
        build_required_tools
        hdr "Dry Run Plan"
        (( MODE_FULL == 1 || MODE_DEEP == 1 )) && printf '[DRY-RUN] Discovery: subfinder -> assetfinder -> amass -> httpx\n'
        (( MODE_FULL == 1 || MODE_URL == 1 )) && printf '[DRY-RUN] URLs: katana + gau + waybackurls + hakrawler -> normalization -> parameter mining\n'
        (( MODE_FULL == 1 || MODE_VULN == 1 )) && printf '[DRY-RUN] Vulnerability checks: nuclei + kxss + dalfox + bounded commix\n'
        (( MODE_FULL == 1 )) && printf '[DRY-RUN] Reporting: Markdown -> HTML -> PDF\n'
        printf '[DRY-RUN] Required dependencies:\n'
        printf '  - %s\n' "${REQUIRED_TOOLS[@]}"
        FINISHED_EPOCH="$(date +%s)"; write_run_json
        ok "Dry run complete. No dependency installation or active scanning was performed."
        return 0
    fi

    check_dependencies || true
    write_run_json

    if (( MODE_FULL == 1 || MODE_DEEP == 1 )); then
        if state_is_completed deep_enum; then DEEP_STATUS="completed"; ok "Skipping completed module: deep_enum"; else module_deep_enum || FINAL_RC=1; fi
    fi
    if (( MODE_FULL == 1 || MODE_URL == 1 )); then
        if state_is_completed url_crawl; then URL_STATUS="completed"; ok "Skipping completed module: url_crawl"; else module_url_crawl || FINAL_RC=1; fi
    fi
    if (( MODE_FULL == 1 || MODE_VULN == 1 )); then
        if state_is_completed vuln_scan; then VULN_STATUS="completed"; ok "Skipping completed module: vuln_scan"; else module_vuln_scan || FINAL_RC=1; fi
    fi
    if (( MODE_FULL == 1 )); then
        if state_is_completed report; then REPORT_STATUS="completed"; ok "Skipping completed module: report"; else generate_report || FINAL_RC=1; fi
    fi

    FINISHED_EPOCH="$(date +%s)"
    write_run_json
    hdr "Done"
    ok "Run directory: $OUTDIR"
    case "$(aggregate_status)" in
        completed|dry-run) ok "Overall status: $(aggregate_status)" ;;
        *) warn "Overall status: $(aggregate_status)" ;;
    esac
    return "$FINAL_RC"
}

if [[ "${BELTU_SOURCE_ONLY:-0}" != "1" ]]; then
    main "$@"
fi

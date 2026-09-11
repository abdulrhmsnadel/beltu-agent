#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/BelTu-Agent.sh"
PASS=0
FAIL=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/beltu-tests.XXXXXXXX")"
TEST_DOMAIN="beltu-test-${PPID}.example.com"
trap 'rm -rf -- "$TMP"' EXIT

# Run CLI tests outside the repository so runtime recon_* output never pollutes the source tree.
cd "$TMP"

pass() { printf '[PASS] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '[FAIL] %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }

run_expect_success() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

run_expect_failure() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then fail "$desc"; else pass "$desc"; fi
}

capture() {
    local outfile="$1"; shift
    "$@" >"$outfile" 2>&1
}

# -----------------------------------------------------------------------------
# Static/syntax checks
# -----------------------------------------------------------------------------
if bash -n "$SCRIPT"; then pass 'bash syntax'; else fail 'bash syntax'; fi
if ! grep -qE '^[[:space:]]*eval([[:space:]]|$)' "$SCRIPT"; then pass 'no eval'; else fail 'no eval'; fi
run_expect_success '--version' "$SCRIPT" --version
run_expect_success '--help' "$SCRIPT" --help
run_expect_success 'legacy source-only environment cannot disable execution' env BELTU_SOURCE_ONLY=1 "$SCRIPT" --version

# ShellCheck is optional in lightweight environments; run it when available.
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -x "$SCRIPT" >/dev/null 2>&1; then pass 'shellcheck'; else fail 'shellcheck'; fi
else
    printf '[SKIP] shellcheck executable not installed\n'
fi

# -----------------------------------------------------------------------------
# CLI conflict and dry-run safety
# -----------------------------------------------------------------------------
run_expect_failure 'dry-run + install rejected' "$SCRIPT" -t example.com -f --dry-run --install
run_expect_failure 'install + no-install rejected' "$SCRIPT" -t example.com -f --install --no-install

# A dry run must never call dependency binaries. Provide a fake PATH command that
# would leave a marker if executed, then assert the marker is absent.
FAKEBIN="$TMP/fakebin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/subfinder" <<'EOF_SUBFINDER'
#!/usr/bin/env bash
printf '%s\n' "unexpected subfinder execution" > "${BELTU_TEST_MARKER:?}"
exit 1
EOF_SUBFINDER
chmod +x "$FAKEBIN/subfinder"
BELTU_TEST_MARKER="$TMP/dryrun-marker" PATH="$FAKEBIN:$PATH" \
    run_expect_success 'dry-run skips dependency execution' "$SCRIPT" -t example.com -d --dry-run --no-install
if [[ ! -e "$TMP/dryrun-marker" ]]; then pass 'dry-run left dependency side effects untouched'; else fail 'dry-run left dependency side effects untouched'; fi

# -----------------------------------------------------------------------------
# Numeric bounds
# -----------------------------------------------------------------------------
run_expect_success 'threads lower bound accepted' "$SCRIPT" -t example.com -d --dry-run --no-install --threads 1
run_expect_success 'threads upper bound accepted' "$SCRIPT" -t example.com -d --dry-run --no-install --threads 100
run_expect_failure 'threads above bound rejected' "$SCRIPT" -t example.com -d --dry-run --no-install --threads 101
run_expect_failure 'rate-limit above bound rejected' "$SCRIPT" -t example.com -d --dry-run --no-install --rate-limit 1001
run_expect_failure 'timeout above bound rejected' "$SCRIPT" -t example.com -d --dry-run --no-install --timeout 301
run_expect_failure 'retries above bound rejected' "$SCRIPT" -t example.com -d --dry-run --no-install --retries 6
run_expect_failure 'commix bound above limit rejected' "$SCRIPT" -t example.com -v --dry-run --no-install --max-injection-targets 101

# -----------------------------------------------------------------------------
# Target validation and module selection
# -----------------------------------------------------------------------------
run_expect_failure 'empty target rejected' "$SCRIPT" -t '' -d --dry-run --no-install
run_expect_failure 'URL rejected' "$SCRIPT" -t 'https://example.com' -d --dry-run --no-install
run_expect_failure 'shell metacharacter rejected' "$SCRIPT" -t 'example.com;id' -d --dry-run --no-install
run_expect_failure 'whitespace rejected' "$SCRIPT" -t 'example .com' -d --dry-run --no-install
run_expect_success 'valid subdomain accepted' "$SCRIPT" -t "sub.$TEST_DOMAIN" -d --dry-run --no-install

for spec in \
    "d:Discovery:URLs:Vulnerability checks:Reporting" \
    "a:URLs:Discovery:Vulnerability checks:Reporting" \
    "v:Vulnerability checks:Discovery:URLs:Reporting"; do
    IFS=: read -r mode required forbidden1 forbidden2 forbidden3 <<< "$spec"
    outfile="$TMP/plan_$mode.txt"
    if capture "$outfile" "$SCRIPT" -t "$TEST_DOMAIN" "-$mode" --dry-run --no-install; then
        if grep -q "\[DRY-RUN\] $required" "$outfile" && \
           ! grep -q "\[DRY-RUN\] $forbidden1" "$outfile" && \
           ! grep -q "\[DRY-RUN\] $forbidden2" "$outfile" && \
           ! grep -q "\[DRY-RUN\] $forbidden3" "$outfile"; then
            pass "module selection -$mode"
        else
            fail "module selection -$mode"
        fi
    else
        fail "module selection -$mode command"
    fi
done

# Full mode must include every legacy stage plus reports.
full_plan="$TMP/plan_f.txt"
if capture "$full_plan" "$SCRIPT" -t "$TEST_DOMAIN" -f --dry-run --no-install; then
    if grep -q '\[DRY-RUN\] Discovery' "$full_plan" && \
       grep -q '\[DRY-RUN\] URLs:' "$full_plan" && \
       grep -q '\[DRY-RUN\] Vulnerability checks' "$full_plan" && \
       grep -q '\[DRY-RUN\] Reporting' "$full_plan"; then
        pass 'module selection -f'
    else
        fail 'module selection -f'
    fi
else
    fail 'module selection -f command'
fi

# -----------------------------------------------------------------------------
# Scope filtering and Katana native scope rules (functions under test)
# -----------------------------------------------------------------------------
# shellcheck disable=SC1091
source "$SCRIPT"
declare -f run_tool_output_arg > "$TMP/original_run_tool_output_arg.sh"
declare -f run_tool_named_output > "$TMP/original_run_tool_named_output.sh"
declare -f run_tool_stdin > "$TMP/original_run_tool_stdin.sh"
declare -f require_tool > "$TMP/original_require_tool.sh"
# Tool discovery must search the project tool directory even when the shell PATH does not.
LOCAL_TOOL_DIR="$TMP/project-tools/bin"
mkdir -p "$LOCAL_TOOL_DIR"
cat > "$LOCAL_TOOL_DIR/beltu-test-tool" <<'EOF_TOOL'
#!/usr/bin/env bash
exit 0
EOF_TOOL
chmod 0755 "$LOCAL_TOOL_DIR/beltu-test-tool"
TOOL_BIN_DIR="$LOCAL_TOOL_DIR"
LOCAL_CARGO_BIN_DIR="$ROOT/.beltu-tools/cargo/bin"
GOBIN_DIR="$ROOT/.does-not-exist/go-bin"
CARGO_BIN_DIR="$ROOT/.does-not-exist/cargo-bin"
if [[ "$(resolve_tool beltu-test-tool)" == "$LOCAL_TOOL_DIR/beltu-test-tool" ]]; then
    pass 'local project tool resolution'
else
    fail 'local project tool resolution'
fi
rm -f "$LOCAL_TOOL_DIR/beltu-test-tool"

SCOPE_FILE="$TMP/scope.txt"
printf '%s\n' 'example.com' '*.example.com' > "$SCOPE_FILE"
if is_in_scope 'example.com' && is_in_scope 'api.example.com' && ! is_in_scope 'example.org'; then
    pass 'scope matching'
else
    fail 'scope matching'
fi

scope_urls_in="$TMP/scope-input.txt"
scope_urls_out="$TMP/scope-output.txt"
printf '%s\n' \
    'https://example.com/' \
    'https://api.example.com/v1' \
    'https://evil.example.org/' > "$scope_urls_in"
filter_in_scope_url_list "$scope_urls_in" "$scope_urls_out"
if grep -qx 'https://example.com/' "$scope_urls_out" && \
   grep -qx 'https://api.example.com/v1' "$scope_urls_out" && \
   ! grep -q 'evil.example.org' "$scope_urls_out"; then
    pass 'scope URL filtering'
else
    fail 'scope URL filtering'
fi

katana_scope="$TMP/katana-scope.txt"
if build_katana_scope_file "$katana_scope" && \
   grep -Fq 'https?://example\.com' "$katana_scope" && \
   grep -Fq '([A-Za-z0-9-]+\.)+example\.com' "$katana_scope"; then
    pass 'Katana native scope pattern generated'
else
    fail 'Katana native scope pattern generated'
fi

# The actual crawl module must pass the generated scope file to Katana and only
# use in-scope seed URLs before the crawler starts.
crawl_test_out="$TMP/crawl-run"
crawl_test_tmp="$TMP/crawl-tmp"
mkdir -p "$crawl_test_out/urls" "$crawl_test_out/subdomains" "$crawl_test_out/vulnerabilities" "$crawl_test_out/metadata" "$crawl_test_out/logs/tools" "$crawl_test_tmp"
OUTDIR="$crawl_test_out"
TMP_DIR="$crawl_test_tmp"
LOG_ROOT="$crawl_test_out/logs"
TOOL_LOG_ROOT="$crawl_test_out/logs/tools"
STATE_FILE="$crawl_test_out/metadata/state.tsv"
RUN_JSON="$crawl_test_out/metadata/run.json"
TARGET='example.com'
SCOPE_FILE="$TMP/scope.txt"
THREADS=10
RATE_LIMIT=5
TIMEOUT=10
RETRIES=1
printf '%s\n' 'https://api.example.com' 'https://evil.example.org' > "$crawl_test_out/subdomains/live_hosts.txt"
: > "$crawl_test_out/urls/urls_with_params.txt"
: > "$crawl_test_out/urls/all_urls.txt"
: > "$crawl_test_out/urls/unique_endpoints.txt"
: > "$crawl_test_out/urls/unique_parameters.txt"
: > "$crawl_test_out/urls/parameterized_endpoints.txt"
KATANA_CAPTURE="$TMP/katana-capture.txt"
run_tool_output_arg() {
    local module="$1" tool="$2" result="$3" input_count="$4"; shift 4
    printf '%s\n' "$tool" "$*" > "$KATANA_CAPTURE"
    : > "$result"
    return 0
}
run_tool_named_output() { local result="$3"; : > "$result"; return 0; }
run_tool_stdin() { local result="$4"; : > "$result"; return 0; }
require_tool() { [[ "$1" == 'katana' || "$1" == 'gau' || "$1" == 'waybackurls' || "$1" == 'hakrawler' ]]; }
if module_url_crawl >/dev/null 2>&1; then
    if grep -q '^https://api.example.com$' "$crawl_test_tmp/crawl_input.txt" && \
       ! grep -q 'evil.example.org' "$crawl_test_tmp/crawl_input.txt" && \
       grep -q -- '-cs' "$KATANA_CAPTURE"; then
        pass 'crawler scope enforcement before Katana'
    else
        fail 'crawler scope enforcement before Katana'
    fi
else
    fail 'crawler scope enforcement module execution'
fi

# Restore the real wrappers after crawl interception.
source "$TMP/original_run_tool_output_arg.sh"
source "$TMP/original_run_tool_named_output.sh"
source "$TMP/original_run_tool_stdin.sh"
source "$TMP/original_require_tool.sh"

# -----------------------------------------------------------------------------
# run_tool_output_arg output ownership: result file comes from -o, stdout stays
# in stdout log, stderr stays in stderr log.
# -----------------------------------------------------------------------------
TOOLBIN="$TMP/toolbin"
mkdir -p "$TOOLBIN"
cat > "$TOOLBIN/fake-output-tool" <<'EOF_FAKE'
#!/usr/bin/env bash
set -u
out=''
while (($# > 0)); do
    case "$1" in
        -o) shift; out="$1" ;;
    esac
    shift
done
printf 'tool-output\n' > "$out"
printf 'stdout-output\n'
printf 'stderr-output\n' >&2
EOF_FAKE
chmod +x "$TOOLBIN/fake-output-tool"
PATH="$TOOLBIN:$PATH"
TOOL_LOG_ROOT="$TMP/tool-logs"
TMP_DIR="$TMP"
mkdir -p "$TOOL_LOG_ROOT"
DRY_RUN=0
result_file="$TMP/result.txt"
if run_tool_output_arg test fake-output-tool "$result_file" 1 --example value; then
    if grep -qx 'tool-output' "$result_file" && \
       grep -qx 'stdout-output' "$TOOL_LOG_ROOT/test_fake-output-tool.stdout.log" && \
       grep -qx 'stderr-output' "$TOOL_LOG_ROOT/test_fake-output-tool.stderr.log"; then
        pass 'run_tool_output_arg output separation'
    else
        fail 'run_tool_output_arg output separation'
    fi
else
    fail 'run_tool_output_arg execution'
fi

# -----------------------------------------------------------------------------
# Deep enumeration failure classification: a seed alone cannot make the stage
# partial/successful when every enumeration/probe tool fails.
# -----------------------------------------------------------------------------
OUTDIR="$TMP/deep-run"
TMP_DIR="$TMP/deep-tmp"
mkdir -p "$OUTDIR/subdomains" "$OUTDIR/metadata" "$OUTDIR/logs/tools" "$TMP_DIR"
LOG_ROOT="$OUTDIR/logs"
TOOL_LOG_ROOT="$OUTDIR/logs/tools"
STATE_FILE="$OUTDIR/metadata/state.tsv"
RUN_JSON="$OUTDIR/metadata/run.json"
TARGET='example.com'
SCOPE_FILE=''
TIMEOUT=10
THREADS=10
RATE_LIMIT=5
RETRIES=1
DEEP_STATUS='not_run'
REQUIRED_TOOLS=()

require_tool() { return 0; }
run_tool_output_arg() { return 1; }
run_tool_stdout() { return 1; }
# Do not invoke the normal network/tool implementations in this isolated unit test.
if module_deep_enum; then
    fail 'deep enum all-tool failure classified as failed'
else
    if [[ "$DEEP_STATUS" == 'failed' ]]; then pass 'deep enum all-tool failure classified as failed'; else fail 'deep enum all-tool failure classified as failed'; fi
fi

# -----------------------------------------------------------------------------
# Resume accumulated duration and state
# -----------------------------------------------------------------------------
RESUME_DIR="$TMP/resume-run"
mkdir -p "$RESUME_DIR/metadata" "$RESUME_DIR/subdomains" "$RESUME_DIR/urls" "$RESUME_DIR/vulnerabilities" "$RESUME_DIR/logs/tools"
printf '%s\n' 'example.com' > "$RESUME_DIR/metadata/target.txt"
printf '%s\n' 'deep_enum\tcompleted\t1\t2\t0\t' > "$RESUME_DIR/metadata/state.tsv"
cat > "$RESUME_DIR/metadata/run.json" <<'EOF_RUNJSON'
{
  "tool": "BelTu-Agent",
  "version": "1.1.2",
  "target": "example.com",
  "started_at": "2026-09-11T00:00:00Z",
  "finished_at": "2026-09-11T00:00:12Z",
  "mode": "full",
  "status": "partial",
  "duration_seconds": 12,
  "resume_count": 2
}
EOF_RUNJSON
TARGET=''; SCOPE_FILE=''; RESUME_DIR="$RESUME_DIR"; OUTDIR=''; RUN_ID=''; ACCUMULATED_DURATION=0; RESUME_COUNT=0; ORIGINAL_STARTED_ISO=''; STARTED_EPOCH=0; STARTED_ISO=''
if load_resume_run; then
    if [[ "$ACCUMULATED_DURATION" == '12' && "$RESUME_COUNT" == '3' && "$STARTED_ISO" == '2026-09-11T00:00:00Z' ]]; then
        pass 'resume preserves accumulated duration and original start'
    else
        fail 'resume preserves accumulated duration and original start'
    fi
    FINISHED_EPOCH=$((STARTED_EPOCH + 3))
    write_run_json
    resumed_duration=$(sed -n 's/^[[:space:]]*"duration_seconds":[[:space:]]*\([0-9][0-9]*\),\{0,1\}.*/\1/p' "$RUN_JSON" | head -n 1)
    if [[ "$resumed_duration" == '15' ]]; then
        pass 'resume writes accumulated total duration'
    else
        fail 'resume writes accumulated total duration'
    fi
else
    fail 'resume load'
fi

# -----------------------------------------------------------------------------
# README consistency checks
# -----------------------------------------------------------------------------
README="$ROOT/README.md"
if grep -q 'v1.1.2' "$README" || grep -q '\*\*1.1.2\*\*' "$README"; then pass 'README version updated'; else fail 'README version updated'; fi
if grep -q 'Per-tool request rate/concurrency' "$README"; then pass 'README rate-limit wording'; else fail 'README rate-limit wording'; fi
if grep -q -- '--dry-run.*--install' "$README"; then pass 'README dry-run/install rule'; else fail 'README dry-run/install rule'; fi
if grep -q 'Katana.*native\|native.*Katana' "$README"; then pass 'README crawler scope enforcement'; else fail 'README crawler scope enforcement'; fi

# Local launcher installation must work even when the source script is executed via a generated wrapper.
LAUNCH_HOME="$TMP/launcher-home"
mkdir -p "$LAUNCH_HOME"
if (cd "$ROOT" && HOME="$LAUNCH_HOME" PATH=/usr/bin:/bin make install-local >/dev/null 2>&1); then
    chmod 0644 "$ROOT/BelTu-Agent.sh"
    launcher_version="$(cd "$TMP" && env -u BELTU_SOURCE_ONLY HOME="$LAUNCH_HOME" PATH="$LAUNCH_HOME/.local/bin:/usr/bin:/bin" "$LAUNCH_HOME/.local/bin/beltu" --version 2>&1)"
    chmod 0755 "$ROOT/BelTu-Agent.sh"
    if [[ "$launcher_version" == 'BelTu-Agent v1.1.2' ]]; then
        pass 'local launcher execution without source executable bit'
    else
        fail 'local launcher execution without source executable bit'
    fi
else
    fail 'local launcher installation'
fi

printf '\nPassed: %d\nFailed: %d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))

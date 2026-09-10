#!/usr/bin/env bash
#
# ============================================================================
#  BelTu-Agent — Recon & Vulnerability Scanning Orchestrator
#  Author: Balto (custom build)
#  Purpose: Authorized security testing / bug bounty recon automation ONLY.
#           Use exclusively against targets you own or are authorized to test.
# ============================================================================

set -uo pipefail
IFS=$'\n\t'

# ----------------------------------------------------------------------------
# GLOBALS
# ----------------------------------------------------------------------------
SCRIPT_NAME="BelTu-Agent"
SCRIPT_VERSION="1.0.0"
GOBIN_DIR="${GOPATH:-$HOME/go}/bin"
export PATH="$PATH:$GOBIN_DIR:/usr/local/go/bin"

TARGET=""
MODE_DEEP=0
MODE_URL=0
MODE_VULN=0
MODE_FULL=0
OUTDIR=""
TS="$(date +%Y%m%d_%H%M%S)"

# Colors
C_RED='\033[0;31m'; C_GRN='\033[0;32m'; C_YLW='\033[1;33m'
C_BLU='\033[0;34m'; C_CYN='\033[0;36m'; C_RST='\033[0m'; C_BLD='\033[1m'

log()  { echo -e "${C_CYN}[*]${C_RST} $*"; }
ok()   { echo -e "${C_GRN}[+]${C_RST} $*"; }
warn() { echo -e "${C_YLW}[!]${C_RST} $*"; }
err()  { echo -e "${C_RED}[x]${C_RST} $*" >&2; }
hdr()  { echo -e "\n${C_BLD}${C_BLU}==== $* ====${C_RST}\n"; }

# ----------------------------------------------------------------------------
# 1. BANNER (password lock removed by request — no auth gate)
# ----------------------------------------------------------------------------
print_banner() {
    echo -e "${C_BLD}${C_CYN}"
    cat <<'BANNER'
 ____       _ _____       _                    _
|  _ \ ___ | |_   _|   __| |    __ _  __ _  ___| |_
| |_) / _ \| | | |___ / _` |   / _` |/ _` |/ _ \ __|
|  _ < (_) | | | |___| (_| |  | (_| | (_| |  __/ |_
|_| \_\___/|_| |_|    \__,_|   \__,_|\__, |\___|\__|
                                     |___/
        BelTu-Agent :: Recon & VulnScan Orchestrator
BANNER
    echo -e "${C_RST}"
}

# ----------------------------------------------------------------------------
# 2. INPUT SANITIZATION — strict domain whitelist, no command injection surface
# ----------------------------------------------------------------------------
sanitize_domain() {
    local raw="$1"
    local clean

    # Strip surrounding whitespace only — no other transformation trusted.
    clean="$(echo -n "$raw" | tr -d '[:space:]')"

    # Hard reject: empty, or containing anything outside a strict domain
    # character set. This alone blocks ;, |, &, $, `, (), <, >, quotes, etc.
    if [[ -z "$clean" ]]; then
        err "Target cannot be empty."
        exit 1
    fi

    if [[ ! "$clean" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; then
        err "Invalid target format: '$raw'"
        err "Only a bare domain/subdomain is accepted (e.g. example.com, sub.example.com)."
        exit 1
    fi

    # Belt-and-suspenders: explicitly reject known shell metacharacters even
    # though the regex above already excludes them.
    case "$clean" in
        *[\;\|\&\$\`\(\)\<\>\"\'\\*\?\ ]*)
            err "Rejected target containing disallowed characters."
            exit 1
            ;;
    esac

    printf '%s' "$clean"
}

# ----------------------------------------------------------------------------
# 3. DEPENDENCY CHECK & AUTO-INSTALL
# ----------------------------------------------------------------------------
detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then echo "apt"; 
    elif command -v pacman &>/dev/null; then echo "pacman";
    elif command -v dnf &>/dev/null; then echo "dnf";
    elif command -v brew &>/dev/null; then echo "brew";
    else echo "none"; fi
}

ensure_go() {
    if command -v go &>/dev/null; then return 0; fi
    warn "Go toolchain not found — installing Go..."
    local pm; pm="$(detect_pkg_manager)"
    case "$pm" in
        apt)    sudo apt-get update -y && sudo apt-get install -y golang-go ;;
        pacman) sudo pacman -Sy --noconfirm go ;;
        dnf)    sudo dnf install -y golang ;;
        brew)   brew install go ;;
        *) err "No supported package manager found to install Go. Install it manually."; return 1 ;;
    esac
    mkdir -p "$GOBIN_DIR"
}

install_tool() {
    local tool="$1"
    log "Installing missing dependency: $tool"

    case "$tool" in
        subfinder)
            ensure_go && go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest ;;
        assetfinder)
            ensure_go && go install -v github.com/tomnomnom/assetfinder@latest ;;
        amass)
            ensure_go && go install -v github.com/owasp-amass/amass/v4/...@master ;;
        httpx)
            ensure_go && go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest ;;
        katana)
            ensure_go && go install -v github.com/projectdiscovery/katana/cmd/katana@latest ;;
        gau)
            ensure_go && go install -v github.com/lc/gau/v2/cmd/gau@latest ;;
        waybackurls)
            ensure_go && go install -v github.com/tomnomnom/waybackurls@latest ;;
        hakrawler)
            ensure_go && go install -v github.com/hakluke/hakrawler@latest ;;
        nuclei)
            ensure_go && go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
            nuclei -update-templates &>/dev/null || true ;;
        dalfox)
            ensure_go && go install -v github.com/hahwul/dalfox/v2@latest ;;
        kxss)
            ensure_go && go install -v github.com/Emoe/kxss@latest ;;
        commix)
            if ! command -v commix &>/dev/null; then
                git clone --depth 1 https://github.com/commixproject/commix.git "$HOME/.beltu-tools/commix" 2>/dev/null
                sudo ln -sf "$HOME/.beltu-tools/commix/commix.py" /usr/local/bin/commix
                sudo chmod +x /usr/local/bin/commix
            fi ;;
        jq|pandoc)
            local pm; pm="$(detect_pkg_manager)"
            case "$pm" in
                apt)    sudo apt-get update -y && sudo apt-get install -y "$tool" ;;
                pacman) sudo pacman -Sy --noconfirm "$tool" ;;
                dnf)    sudo dnf install -y "$tool" ;;
                brew)   brew install "$tool" ;;
                *) err "Install '$tool' manually — no supported package manager detected." ;;
            esac ;;
        weasyprint)
            if command -v pip3 &>/dev/null; then
                pip3 install --user --break-system-packages weasyprint 2>/dev/null || pip3 install --user weasyprint
            else
                warn "pip3 not found; skipping weasyprint (pandoc PDF fallback will be used)."
            fi ;;
        *)
            warn "No known installer for '$tool'. Please install it manually." ;;
    esac
}

check_dependencies() {
    hdr "Dependency Check"
    local required=(subfinder assetfinder amass httpx katana gau waybackurls hakrawler nuclei dalfox kxss commix jq pandoc weasyprint)
    local missing=()

    for tool in "${required[@]}"; do
        if command -v "$tool" &>/dev/null; then
            ok "$tool found"
        else
            warn "$tool missing"
            missing+=("$tool")
        fi
    done

    if (( ${#missing[@]} == 0 )); then
        ok "All dependencies satisfied."
        return 0
    fi

    warn "Missing ${#missing[@]} tool(s): ${missing[*]}"
    read -rp "$(echo -e "${C_YLW}[?]${C_RST} Attempt automatic installation now? [Y/n]: ")" reply
    reply="${reply:-Y}"
    if [[ "$reply" =~ ^[Yy] ]]; then
        for tool in "${missing[@]}"; do
            install_tool "$tool"
        done
        hash -r
        log "Re-checking after installation attempt..."
        for tool in "${missing[@]}"; do
            if command -v "$tool" &>/dev/null; then
                ok "$tool now available"
            else
                err "$tool still unavailable — module(s) needing it will be skipped."
            fi
        done
    else
        warn "Skipping auto-install; modules requiring missing tools will be skipped."
    fi
}

require() {
    # returns 0/1 and prints a warning if a specific tool is unavailable
    command -v "$1" &>/dev/null || { warn "Skipping step: '$1' not installed."; return 1; }
}

# ----------------------------------------------------------------------------
# 4. MODULE: DEEP SUBDOMAIN ENUMERATION & ACTIVE HOST PROBING  (-d)
# ----------------------------------------------------------------------------
module_deep_enum() {
    hdr "Deep Subdomain Enumeration & Active Host Probing"
    local sub_dir="$OUTDIR/subdomains"
    mkdir -p "$sub_dir"
    local all_subs="$sub_dir/all_subdomains.txt"
    : > "$all_subs"

    if require subfinder; then
        log "Running subfinder..."
        subfinder -d "$TARGET" -all -silent -o "$sub_dir/subfinder.txt" 2>>"$sub_dir/errors.log"
        cat "$sub_dir/subfinder.txt" 2>/dev/null >> "$all_subs"
    fi

    if require assetfinder; then
        log "Running assetfinder..."
        assetfinder --subs-only "$TARGET" > "$sub_dir/assetfinder.txt" 2>>"$sub_dir/errors.log"
        cat "$sub_dir/assetfinder.txt" 2>/dev/null >> "$all_subs"
    fi

    if require amass; then
        log "Running amass (passive, bounded)..."
        timeout 600 amass enum -passive -d "$TARGET" -o "$sub_dir/amass.txt" 2>>"$sub_dir/errors.log"
        cat "$sub_dir/amass.txt" 2>/dev/null >> "$all_subs"
    fi

    sort -u "$all_subs" -o "$all_subs"
    local sub_count; sub_count=$(wc -l < "$all_subs" 2>/dev/null || echo 0)
    ok "Collected $sub_count unique subdomains -> $all_subs"

    if require httpx; then
        log "Probing live hosts with httpx..."
        httpx -l "$all_subs" -silent -status-code -title -tech-detect -json \
              -o "$sub_dir/httpx_results.json" 2>>"$sub_dir/errors.log"
        httpx -l "$all_subs" -silent -o "$sub_dir/live_hosts.txt" 2>>"$sub_dir/errors.log"
        local live_count; live_count=$(wc -l < "$sub_dir/live_hosts.txt" 2>/dev/null || echo 0)
        ok "Live hosts: $live_count -> $sub_dir/live_hosts.txt"
    fi
}

# ----------------------------------------------------------------------------
# 5. MODULE: URL CRAWLING & PARAMETER MINING  (-a)
# ----------------------------------------------------------------------------
module_url_crawl() {
    hdr "URL Crawling & Parameter Mining"
    local url_dir="$OUTDIR/urls"
    mkdir -p "$url_dir"
    local live_hosts="$OUTDIR/subdomains/live_hosts.txt"
    local seed_target="$TARGET"
    local all_urls="$url_dir/all_urls.txt"
    : > "$all_urls"

    # Use previously discovered live hosts if the -d module already ran,
    # otherwise fall back to the bare target.
    local crawl_input
    if [[ -s "$live_hosts" ]]; then
        crawl_input="$live_hosts"
    else
        crawl_input=$(mktemp)
        echo "$seed_target" > "$crawl_input"
    fi

    if require katana; then
        log "Running katana..."
        katana -list "$crawl_input" -silent -jc -kf all -o "$url_dir/katana.txt" 2>>"$url_dir/errors.log"
        cat "$url_dir/katana.txt" 2>/dev/null >> "$all_urls"
    fi

    if require gau; then
        log "Running gau..."
        gau --subs "$seed_target" > "$url_dir/gau.txt" 2>>"$url_dir/errors.log"
        cat "$url_dir/gau.txt" 2>/dev/null >> "$all_urls"
    fi

    if require waybackurls; then
        log "Running waybackurls..."
        echo "$seed_target" | waybackurls > "$url_dir/waybackurls.txt" 2>>"$url_dir/errors.log"
        cat "$url_dir/waybackurls.txt" 2>/dev/null >> "$all_urls"
    fi

    if require hakrawler; then
        log "Running hakrawler..."
        echo "https://$seed_target" | hakrawler -d 2 > "$url_dir/hakrawler.txt" 2>>"$url_dir/errors.log"
        cat "$url_dir/hakrawler.txt" 2>/dev/null >> "$all_urls"
    fi

    sort -u "$all_urls" -o "$all_urls"
    local url_count; url_count=$(wc -l < "$all_urls" 2>/dev/null || echo 0)
    ok "Collected $url_count unique URLs -> $all_urls"

    # Extract URLs that carry parameters (candidates for injection testing)
    grep -E '\?[a-zA-Z0-9_]+=' "$all_urls" 2>/dev/null | sort -u > "$url_dir/urls_with_params.txt"
    local param_count; param_count=$(wc -l < "$url_dir/urls_with_params.txt" 2>/dev/null || echo 0)
    ok "URLs with parameters: $param_count -> $url_dir/urls_with_params.txt"
}

# ----------------------------------------------------------------------------
# 6. MODULE: VULNERABILITY SCANNING SUITE  (-v)
# ----------------------------------------------------------------------------
module_vuln_scan() {
    hdr "Vulnerability Scanning Suite"
    local vuln_dir="$OUTDIR/vulnerabilities"
    mkdir -p "$vuln_dir"

    local live_hosts="$OUTDIR/subdomains/live_hosts.txt"
    local param_urls="$OUTDIR/urls/urls_with_params.txt"
    local scan_target_list
    if [[ -s "$live_hosts" ]]; then
        scan_target_list="$live_hosts"
    else
        scan_target_list=$(mktemp)
        echo "https://$TARGET" > "$scan_target_list"
    fi

    if require nuclei; then
        log "Running nuclei (this may take a while)..."
        nuclei -l "$scan_target_list" -silent -severity low,medium,high,critical \
               -jsonl -o "$vuln_dir/nuclei_results.jsonl" 2>>"$vuln_dir/errors.log"
        local nfindings; nfindings=$(wc -l < "$vuln_dir/nuclei_results.jsonl" 2>/dev/null || echo 0)
        ok "nuclei findings: $nfindings"
    fi

    if [[ -s "$param_urls" ]]; then
        if require kxss; then
            log "Running kxss for reflected-parameter discovery..."
            cat "$param_urls" | kxss > "$vuln_dir/kxss_results.txt" 2>>"$vuln_dir/errors.log"
            ok "kxss output -> $vuln_dir/kxss_results.txt"
        fi

        if require dalfox; then
            log "Running dalfox XSS scan on parameterized URLs..."
            dalfox file "$param_urls" --silence --no-color -o "$vuln_dir/dalfox_results.txt" 2>>"$vuln_dir/errors.log"
            ok "dalfox output -> $vuln_dir/dalfox_results.txt"
        fi

        if require commix; then
            log "Running commix on a bounded sample of parameterized URLs..."
            : > "$vuln_dir/commix_results.txt"
            head -n 20 "$param_urls" | while IFS= read -r u; do
                timeout 60 commix --batch -u "$u" >> "$vuln_dir/commix_results.txt" 2>>"$vuln_dir/errors.log" || true
            done
            ok "commix output -> $vuln_dir/commix_results.txt"
        fi
    else
        warn "No parameterized URLs found — skipping kxss/dalfox/commix (run -a first for best results)."
    fi
}

# ----------------------------------------------------------------------------
# 7. REPORT GENERATION — Markdown + PDF
# ----------------------------------------------------------------------------
generate_report() {
    hdr "Compiling Executive Security Assessment Report"
    local report_md="$OUTDIR/report.md"
    local sub_count url_count param_count nuclei_count

    sub_count=$(wc -l < "$OUTDIR/subdomains/all_subdomains.txt" 2>/dev/null || echo 0)
    url_count=$(wc -l < "$OUTDIR/urls/all_urls.txt" 2>/dev/null || echo 0)
    param_count=$(wc -l < "$OUTDIR/urls/urls_with_params.txt" 2>/dev/null || echo 0)
    nuclei_count=$(wc -l < "$OUTDIR/vulnerabilities/nuclei_results.jsonl" 2>/dev/null || echo 0)

    {
        echo "# Security Assessment Report"
        echo
        echo "**Target:** \`$TARGET\`  "
        echo "**Generated:** $(date '+%Y-%m-%d %H:%M:%S %Z')  "
        echo "**Tool:** $SCRIPT_NAME v$SCRIPT_VERSION"
        echo
        echo "---"
        echo
        echo "## Executive Summary"
        echo
        echo "| Metric | Count |"
        echo "|---|---|"
        echo "| Unique subdomains discovered | $sub_count |"
        echo "| Unique URLs crawled | $url_count |"
        echo "| URLs with parameters | $param_count |"
        echo "| Nuclei findings | $nuclei_count |"
        echo
        echo "---"
        echo
        echo "## 1. Subdomain Enumeration"
        echo
        if [[ -s "$OUTDIR/subdomains/live_hosts.txt" ]]; then
            echo "### Live Hosts"
            echo '```'
            cat "$OUTDIR/subdomains/live_hosts.txt"
            echo '```'
        else
            echo "_No live host data available._"
        fi
        echo
        echo "---"
        echo
        echo "## 2. URL Crawling & Parameter Mining"
        echo
        echo "- Total unique URLs: **$url_count**"
        echo "- URLs carrying parameters: **$param_count**"
        echo
        echo "---"
        echo
        echo "## 3. Vulnerability Findings"
        echo
        if [[ -s "$OUTDIR/vulnerabilities/nuclei_results.jsonl" ]]; then
            echo "### Nuclei"
            echo '```json'
            head -c 4000 "$OUTDIR/vulnerabilities/nuclei_results.jsonl"
            echo '```'
        fi
        if [[ -s "$OUTDIR/vulnerabilities/kxss_results.txt" ]]; then
            echo "### Reflected Parameters (kxss)"
            echo '```'
            cat "$OUTDIR/vulnerabilities/kxss_results.txt"
            echo '```'
        fi
        if [[ -s "$OUTDIR/vulnerabilities/dalfox_results.txt" ]]; then
            echo "### XSS Findings (dalfox)"
            echo '```'
            cat "$OUTDIR/vulnerabilities/dalfox_results.txt"
            echo '```'
        fi
        if [[ -s "$OUTDIR/vulnerabilities/commix_results.txt" ]]; then
            echo "### Command Injection Probes (commix)"
            echo '```'
            cat "$OUTDIR/vulnerabilities/commix_results.txt"
            echo '```'
        fi
        echo
        echo "---"
        echo
        echo "## Disclaimer"
        echo "This report was generated by an automated tool for authorized security"
        echo "testing purposes only. All findings require manual verification before"
        echo "being reported or acted upon."
    } > "$report_md"

    ok "Markdown report -> $report_md"

    local report_pdf="$OUTDIR/report.pdf"
    if command -v pandoc &>/dev/null; then
        log "Compiling PDF via pandoc..."
        if pandoc "$report_md" -o "$report_pdf" --pdf-engine=weasyprint 2>/dev/null \
           || pandoc "$report_md" -o "$report_pdf" 2>/dev/null; then
            ok "PDF report -> $report_pdf"
        else
            warn "pandoc PDF generation failed; trying weasyprint fallback via HTML."
            if command -v pandoc &>/dev/null && command -v weasyprint &>/dev/null; then
                pandoc "$report_md" -o "$OUTDIR/report.html" 2>/dev/null
                weasyprint "$OUTDIR/report.html" "$report_pdf" 2>/dev/null \
                    && ok "PDF report -> $report_pdf" \
                    || warn "PDF generation failed. Markdown report is still available."
            fi
        fi
    else
        warn "pandoc not installed — only the Markdown report was generated."
    fi
}

# ----------------------------------------------------------------------------
# 8. USAGE
# ----------------------------------------------------------------------------
usage() {
    cat <<EOF
${C_BLD}$SCRIPT_NAME v$SCRIPT_VERSION${C_RST}

Usage: $0 -t <target-domain> [MODE]

Modes (choose one or more):
  -d          Deep subdomain enumeration & active host probing
  -a          URL crawling & parameter mining
  -v          Vulnerability scanning suite
  -f          Full pipeline: -d + -a + -v + PDF report

Other:
  -t <domain> Target domain (required), e.g. -t example.com
  -h          Show this help message

Example:
  $0 -t example.com -f
EOF
}

# ----------------------------------------------------------------------------
# 9. MAIN
# ----------------------------------------------------------------------------
main() {
    if [[ $# -eq 0 ]]; then usage; exit 1; fi

    while getopts ":t:davfh" opt; do
        case "$opt" in
            t) TARGET_RAW="$OPTARG" ;;
            d) MODE_DEEP=1 ;;
            a) MODE_URL=1 ;;
            v) MODE_VULN=1 ;;
            f) MODE_FULL=1 ;;
            h) usage; exit 0 ;;
            \?) err "Invalid option: -$OPTARG"; usage; exit 1 ;;
            :)  err "Option -$OPTARG requires an argument."; usage; exit 1 ;;
        esac
    done

    if [[ -z "${TARGET_RAW:-}" ]]; then
        err "Target domain is required (-t <domain>)."
        usage
        exit 1
    fi

    if (( MODE_DEEP == 0 && MODE_URL == 0 && MODE_VULN == 0 && MODE_FULL == 0 )); then
        err "No mode selected. Use -d, -a, -v, or -f."
        usage
        exit 1
    fi

    print_banner

    TARGET="$(sanitize_domain "$TARGET_RAW")"
    ok "Sanitized target: $TARGET"

    OUTDIR="recon_${TARGET}_${TS}"
    mkdir -p "$OUTDIR"
    ok "Output directory: $OUTDIR"

    check_dependencies

    if (( MODE_FULL == 1 )); then
        module_deep_enum
        module_url_crawl
        module_vuln_scan
        generate_report
    else
        (( MODE_DEEP == 1 )) && module_deep_enum
        (( MODE_URL  == 1 )) && module_url_crawl
        (( MODE_VULN == 1 )) && module_vuln_scan
    fi

    hdr "Done"
    ok "All artifacts saved under: $OUTDIR"
}

main "$@"

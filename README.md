# BELTU 1.1.0

BELTU is a local-first agentic security-testing platform for **explicitly authorized** assessments. It keeps the reasoning loop, persistent state, evidence, reporting, scope controls, approval gates, and tool execution in separate layers so the system can reason over evidence without turning the language model into an unrestricted command runner.

The 1.1.0 upgrade adds a **local FreeToken inference path** and a product-style mobile Command Center. FreeToken is an edge-native MoE serving engine with OpenAI-compatible APIs and CPU/GPU/host-memory execution strategies. Its documented server command is `ft serve`; BELTU deliberately runs its local instance on `127.0.0.1:8000` to keep the BELTU/FreeToken contract isolated.

## What BELTU does

```text
Authorized Target
      ↓
Persistent Scan State
      ↓
Observe → Hypothesize → Plan → Policy → Act
      ↓
Evidence + Correlation
      ↓
Re-evaluate / Re-plan
      ↓
Findings + Reports
```

BELTU's LLM is a **reasoning component**, not a shell. The model returns structured hypotheses and declarative actions; the scope guard, approval system, capability registry, resource governor, and execution layer decide whether anything can actually run.

## Safety defaults

- Targets are default-deny and must be explicitly present in `config/scope.yaml`.
- High-risk actions require a validated approval record.
- External tools remain policy-controlled and are **disabled by default** in the repository configuration.
- FreeToken reasoning is loopback-only; BELTU rejects a non-loopback FreeToken base URL.
- Remote API binds to `127.0.0.1` by default and requires authentication.
- Runtime databases, evidence, tokens, model weights, and `.env` files are not meant to be committed to Git.

## Requirements

### BELTU

- Linux (Kali/Ubuntu recommended)
- Python 3.11+
- Git
- `venv` support
- Python dependencies declared in `pyproject.toml`

### Security tools

Install only the tools that match the capabilities you intend to enable:

| Tool | Capability | Purpose |
|---|---|---|
| Subfinder | `asset.discovery.subdomains` | passive subdomain discovery |
| Assetfinder | `asset.discovery.subdomains` | passive asset discovery |
| Amass | `asset.discovery.subdomains` | passive DNS/asset enrichment |
| Httpx | `web.verify` | HTTP service verification |
| Nmap | `service.discovery` | service discovery |
| Nuclei | `web.vulnerability_detection` | template-based candidate detection |

BELTU does not require every tool for the CLI, database, reasoning, reporting, or remote gateway to start.

## Installation

```bash
cd ~/BELTU
python3 -m venv .venv
source .venv/bin/activate
python -m ensurepip --upgrade
python -m pip install -U pip setuptools wheel
python -m pip install -e . --no-build-isolation

beltu doctor --strict
beltu status
```

Configure `config/scope.yaml` with **only targets you are authorized to test**.

## Local FreeToken AI

The repository contains:

- `scripts/install_local_ai.sh`
- `scripts/start_local_ai.sh`
- `scripts/stop_local_ai.sh`
- local provider under `src/beltu/brain/llm/provider.py`
- GPU/VRAM-aware resource governance under `src/beltu/execution/resource_governor.py`

Example:

```bash
chmod +x scripts/install_local_ai.sh scripts/start_local_ai.sh scripts/stop_local_ai.sh

export BELTU_FREETOKEN_MODEL=/absolute/path/to/local/model
scripts/install_local_ai.sh
scripts/start_local_ai.sh

curl http://127.0.0.1:8000/v1/models
beltu llm
beltu resources
```

For a truly air-gapped deployment, preload FreeToken source and local model weights before disconnecting the host. BELTU's provider rejects non-loopback FreeToken endpoints, so the reasoning path does not silently fall back to a cloud URL.

## CLI reference

| Command | Use | Example |
|---|---|---|
| `beltu target <domain>` | validate scope and register target | `beltu target example.com` |
| `beltu targets` | list registered targets | `beltu targets` |
| `beltu hunt <domain>` | start the persistent BELTU reasoning lifecycle | `beltu hunt example.com` |
| `beltu status` | show active scans and local resource/AI state | `beltu status` |
| `beltu resources` | show CPU/RAM/GPU/FreeToken telemetry | `beltu resources` |
| `beltu llm` | show local reasoning configuration | `beltu llm` |
| `beltu tools` | show tool adapters and approval metadata | `beltu tools` |
| `beltu remote` | start the authenticated Mobile Command Center gateway | `beltu remote` |
| `beltu remote-doctor` | validate remote environment | `beltu remote-doctor` |
| `beltu doctor --strict` | run static release/security checks | `beltu doctor --strict` |
| `beltu report <scan-id>` | generate report packages | `beltu report 1` |
| `beltu findings <scan-id>` | show finding candidates | `beltu findings 1` |
| `beltu approval ...` | inspect/resolve persistent approvals | `beltu approval --help` |

Advanced lifecycle and intelligence commands remain available under the `scan`, `asset-inventory`, `surface-rank`, `api-inventory`, `auth-inventory`, `authz-inventory`, `business-workflows`, `capability-rank`, and related command groups.

## Mobile Command Center

The Flutter source is under `mobile/` and provides:

- Dashboard with asset and CPU/RAM/GPU/FreeToken telemetry
- Agent Chat
- Approval queue
- Live WebSocket events
- Workspace file browser
- Markdown/JSON/TXT preview
- Report-package browsing and download

For an Android emulator:

```bash
cd mobile
flutter pub get
flutter run --dart-define=BELTU_BASE_URL=http://10.0.2.2:8765
```

A physical phone needs a trusted reachable server. Do not expose the unauthenticated development gateway to the public internet.

## Remote gateway

Set secure environment variables before starting:

```bash
export BELTU_REMOTE_USER=beltu
export BELTU_REMOTE_PASSWORD='choose-a-strong-password'
export BELTU_REMOTE_SECRET="$(python -c 'import secrets; print(secrets.token_hex(32))')"
export BELTU_REMOTE_HOST=127.0.0.1
export BELTU_REMOTE_PORT=8765

beltu remote
```

Health check:

```bash
curl http://127.0.0.1:8765/health
```

## Workspace

Each scan keeps artifacts under:

```text
data/targets/<target>/scan-<id>/
├── reports/
├── findings/
├── evidence/
├── data/
└── agent/
```

Reports are separated from agent activity, execution history, evidence, structured intelligence, and finding packages so an engagement can be reconstructed later.

## Resource governance

BELTU samples BELTU CPU/RSS, host pressure, NVIDIA VRAM/utilization when available, and FreeToken process statistics. The resource governor converts this telemetry into conservative per-tool limits and can apply CPU affinity restrictions to BELTU-managed child processes under pressure.

This is adaptive throttling, not a claim of an exact 30% OS-level quota for every third-party process.

## Project release

BELTU 1.1.0 keeps the persistent reasoning architecture and adds local FreeToken inference, adaptive GPU/CPU resource telemetry, simplified CLI entry points, mobile remote operations, and expanded reporting/workspace support.

All use is intended for systems and targets for which you have explicit authorization.

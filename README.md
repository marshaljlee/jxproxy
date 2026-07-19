# jxproxy

Another claude experiment. free-claude-code, free-code & Claude On Android

> One binary. Zero callbacks home. Proxy-routed Claude Code for every platform.

**jxproxy** is a self-contained downstream fork of Claude Code with:

- **Proxy-routed API connections** — all Anthropic traffic is intercepted by an embedded proxy server, giving you full control over where and how models are accessed
- **Telemetry stripped** — OpenTelemetry/gRPC, Sentry, GrowthBook analytics, and custom event logging are dead-code-eliminated or stubbed. No crash reports, no usage analytics, no session fingerprinting
- **All guardrails removed** — the extra prompt-level injection layers (hardcoded refusal patterns, "cyber risk" instruction blocks, managed-settings security overlays) are stripped. The model's own safety training still applies
- **54 experimental features unlocked** — all compile-clean feature flags are enabled via `bun:bundle` switches. ULTRAPLAN, ULTRATHINK, BRIDGE_MODE, VOICE_MODE, AGENT_TRIGGERS, CACHED_MICROCOMPACT, and 48 more
- **One binary** — the entire modified CLI is compiled into a single `bun build --compile` binary with no runtime dependencies
- **Cross-platform** — macOS (arm64/x64), Linux (arm64/x64), Android (Termux via ELF patching), Windows (x64/arm64), and iOS (a-Shell/iSH) supported

## Quick Start

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/install.sh | bash

# Android (Termux) — interactive, pre-installs all providers
curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/install-jxproxy-termux.sh | bash

# Alpine Linux
curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/install-alpine.sh | sh

# Windows (PowerShell)
iwr -useb https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/install.ps1 | iex
```

Then:

```bash
# Start jxproxy (launches proxy + modified Claude CLI)
jxproxy

# Or use just the proxy (for the official Claude Code binary too)
jxproxy --proxy-only

# Pass through flags to Claude
jxproxy -- --help
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    jxproxy launcher                      │
│  ┌─────────────────────┐    ┌─────────────────────────┐  │
│  │   jxproxy CLI        │    │   jxproxy Proxy Server  │  │
│  │ (modified Claude     │◄──►│  (TypeScript, embedded) │  │
│  │  Code binary)        │    │                         │  │
│  │                      │    │  ┌───────────────────┐  │  │
│  │  • No telemetry      │    │  │ Model Router      │  │  │
│  │  • No guardrails     │    │  │ • Anthropic       │  │  │
│  │  • All features      │    │  │ • OpenRouter      │  │  │
│  │  • ANTHROPIC_BASE_URL│    │  │ • OpenAI Codex    │  │  │
│  │    → localhost:PORT  │    │  │ • Local LLMs      │  │  │
│  └─────────────────────┘    │  │ • Custom endpoints │  │  │
│                              │  └───────────────────┘  │  │
│                              └─────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### The CLI sends API requests to `http://127.0.0.1:<port>` instead of `api.anthropic.com`.
### The proxy routes them to your configured provider (Anthropic, OpenRouter, local LLM, etc.).
### The proxy handles protocol conversion, model routing, and provider failover.

## What's Different From Upstream Claude Code

### Telemetry Removed
| System | What Changed |
|--------|-------------|
| OpenTelemetry/gRPC | Entire instrumentation layer removed. No spans, no traces, no export. |
| Sentry | Error reporting stubbed. Crashes go to stderr only. |
| GrowthBook | Feature flag evaluation kept local (needed for runtime gates); reporting channel severed. |
| Custom event logging | All `recordEvent`, `trackMetric`, `logAction` calls stripped. |
| Session fingerprinting | No device ID generation or transmission. |

### Guardrails Removed
| Layer | Action Taken |
|-------|-------------|
| Hardcoded refusal patterns | System-prompt injection code removed from conversation pipeline. |
| "Cyber risk" instruction blocks | Injected safety preamble stripped from system messages. |
| Managed-settings security overlays | Server-pushed policy blocks removed. Settings evaluated locally only. |

### Features Unlocked
All 54 compile-clean feature flags enabled, including:
- `ULTRAPLAN` — remote multi-agent planning
- `ULTRATHINK` — deep thinking mode with boosted reasoning
- `VOICE_MODE` — push-to-talk voice input
- `BRIDGE_MODE` — IDE remote-control bridge
- `AGENT_TRIGGERS` — local cron/trigger automation
- `EXTRACT_MEMORIES` — post-query memory extraction
- `VERIFICATION_AGENT` — task validation agent
- `BASH_CLASSIFIER` — classifier-assisted permission decisions
- `TOKEN_BUDGET` — token usage tracking and warnings
- `TEAMMEM` — team-memory files and watcher hooks
- `PROMPT_CACHE_BREAK_DETECTION` — cache-break detection
- `MESSAGE_ACTIONS` — message action entrypoints
- `BUILTIN_EXPLORE_PLAN_AGENTS` — built-in explore/plan agents
- `CACHED_MICROCOMPACT` — microcompact state caching
- `COMPACTION_REMINDERS` — compaction reminder copy
- `QUICK_SEARCH` — prompt quick-search

See [FEATURES.md](docs/FEATURES.md) for the full audit of all 88 flags.

## Platform Support

| Platform | Status | Method |
|----------|--------|--------|
| macOS (arm64) | ✅ | Native `bun build --compile` binary |
| macOS (x64) | ✅ | Native `bun build --compile` binary |
| Linux (x64/arm64) | ✅ | Native `bun build --compile` binary |
| Android (Termux) | ✅ | Official linux-arm64 binary + ELF interpreter patching via `glibc-runner` |
| Alpine Linux (arm64/x64) | ✅ | Same linux-arm64/x64 binaries via gcompat (glibc ABI shim) |
| Windows (x64) | ✅ | `bun build --compile --target windows` |
| Windows 11 on ARM | ✅ | `bun build --compile --target bun-windows-arm64` (Bun 1.2+ auto-detected) |
| iOS (a-Shell/iSH) | 🚧 Experimental | Linux arm64 binary via iSH appstore version |

## Android (ARM64) — Termux Installer

The `install-jxproxy-termux.sh` installer does it all in one run:

```bash
# Install Termux from F-Droid, then:
curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/install-jxproxy-termux.sh | bash
```

What the installer handles:

| Step | What it does |
|------|-------------|
| Dependencies | Installs `glibc-runner` for glibc binary compatibility on Bionic |
| Binaries | Downloads `jxproxy-cli` + `jxproxy-proxy` from GitHub Releases |
| Launcher | Installs `android-launcher.sh` as `~/.local/bin/jxproxy` |
| Config | Writes `~/.jxproxy/config.env` with all providers pre-configured |
| PATH | Prepends `~/.local/bin` so `claude` → jxproxy takes priority |
| Official launcher | Renames `/usr/bin/claude` → `claude-official` so it never interferes |
| Symlink | Creates `~/.local/bin/claude` → `~/.local/bin/jxproxy` |
| `.bashrc` / `.profile` | Writes clean files with jxproxy env vars, no duplicates |
| API wizard | If running interactively, prompts to paste API keys for each provider |

After install, just run `claude` — no alias needed, no official Anthropic code involved.

### Provider chain (default config)

```
opencode/big-pickle  ──►  nvidia/nemotron-3-ultra  ──►  z.ai/glm-5.2
  (primary)                   (fallback 1)                (fallback 2)
```

### Revisiting API key setup

```bash
jxproxy --setup-api    # opens config.env in nano
# or directly:
nano ~/.jxproxy/config.env
```

### jxcode Flutter app

The jxcode app connects to jxproxy on port 5255 using API mode (HTTP requests to `/v1/messages`). Same proxy, same config.

## Configuration

Set environment variables or create `~/.jxproxy/config.env` (the installer does this for you):

```bash
# --- Proxy Configuration ---
JXPROXY_PORT=5255
JXPROXY_AUTH_TOKEN=jxproxy
JXPROXY_PROVIDER=opencode-zen

# Default model
MODEL=opencode/big-pickle
ENABLE_MODEL_THINKING=true

# Tiered model routing
MODEL_OPUS=opencode/big-pickle
MODEL_SONNET=nvidia/nemotron-3-ultra-550b-a55b
MODEL_HAIKU=z/glm-5.2

# Fallback chain (tried in order if primary provider fails)
FALLBACK_PROVIDERS=nvidia,z.ai

# --- Provider Credentials ---
# OPENCODE_API_KEY=sk-oc-...       # Primary: OpenCode
# OPENAI_API_KEY=nvapi-...         # Fallback: NVIDIA NIM
# ZAI_API_KEY=zai-...              # Fallback: z.ai

# --- Provider Selection ---
# Options for JXPROXY_PROVIDER:
#   direct       — use ANTHROPIC_API_KEY directly (default)
#   openrouter   — route via OpenRouter
#   opencode-zen — route via OpenCode Zen (opencode.ai/zen/v1)
#   opencode-go  — route via OpenCode Go (opencode.ai/zen/go/v1)
#   openai       — translate to OpenAI-compatible API
#   zai          — translate to z.ai API (api.z.ai/v1)
#   local        — connect to a local LLM (Ollama, LM Studio, llama.cpp)

# --- z.ai (OpenAI-compatible fallback) ---
ZAI_BASE_URL=https://api.z.ai/v1
# ZAI_API_KEY=

# --- Local LLM (when JXPROXY_PROVIDER=local) ---
LOCAL_LLM_BASE_URL=http://127.0.0.1:11434/v1
LOCAL_LLM_MODEL=ollama/qwen3:latest
```

## Proxy Provider Backends

All providers using OpenAI Chat protocol (codex, gemini, gpt, deepseek, mistral, groq, grok, etc.) work through the generic `openai` backend — just point `JXPROXY_PROVIDER=openai` and set `MODEL` to your upstream model name. Similarly, any Anthropic Messages provider works through the `direct` backend with a custom `ANTHROPIC_BASE_URL`.

| Provider | Protocol | Implemented | Notes |
|----------|----------|-------------|-------|
| Anthropic Direct | Messages | ✅ `direct` | Uses `ANTHROPIC_API_KEY` |
| OpenRouter | Messages | ✅ `openrouter` | Uses `OPENROUTER_API_KEY` |
| OpenCode Zen | OpenAI Chat | ✅ `opencode-zen` | `opencode.ai/zen/v1`, uses `OPENCODE_API_KEY` |
| OpenCode Go | OpenAI Chat | ✅ `opencode-go` | `opencode.ai/zen/go/v1`, shares `OPENCODE_API_KEY` |
| OpenAI / Codex | OpenAI Chat | ✅ `openai` | Uses `OPENAI_API_KEY` |
| Local (Ollama, LM Studio, llama.cpp) | OpenAI Chat | ✅ `local` | Configure `LOCAL_LLM_BASE_URL` + `LOCAL_LLM_MODEL` |
| z.ai (GLM-5.2, GLM-5, Qwen3) | OpenAI Chat | ✅ `zai` | Native `zai` provider — `ZAI_BASE_URL` + `ZAI_API_KEY`. Maps from `z.ai` in `FALLBACK_PROVIDERS` |
| Google Gemini / AWS Bedrock / Vertex / DeepSeek / Mistral / Groq / Grok / Fireworks / NVIDIA NIM | Varies | 🔧 Via `openai` or `direct` | Set `JXPROXY_PROVIDER=openai` + custom `OPENAI_BASE_URL` and `OPENAI_API_KEY` |

## Building From Source

```bash
# Prerequisites: Bun 1.3.11+
curl -fsSL https://bun.sh/install | bash

# Clone and build
git clone https://github.com/marshaljlee/jxproxy.git
cd jxproxy
bun install

# Build the modified Claude Code binary with all features
bun run build

# Build the proxy server separately
bun run build:proxy

# Build both into a single deployable bundle
bun run build:all

# Output goes to ./dist/
#   dist/jxproxy       — the combined binary (launcher + proxy + CLI)
#   dist/jxproxy-proxy — just the proxy server binary
```

## How It Works (The Technical Details)

### Telemetry Stripping
The telemetry removal is done at the source level through a combination of:

1. **Patch files** — targeted patches remove or stub outbound telemetry calls in:
   - `src/services/api/` — API client instrumentation
   - `src/services/analytics/` — GrowthBook reporting
   - `src/services/error/` — Sentry initialization and capture calls
   - Any file importing `@opentelemetry/*` packages

2. **Build-time exclusion** — `bun build --external` for telemetry SDK packages that can't be cleanly removed means they're never included in the binary

3. **Compile-time flag gating** — telemetry-related code paths are gated behind build flags that are never set

### Guardrail Removal
The extra prompt-level restrictions injected by upstream are removed by:
1. Stripping hardcoded refusal response templates from the conversation system prompts
2. Removing the "cyber risk" preamble assembly code
3. Eliminating managed-settings polling and overlay application
4. Keeping all standard model safety training intact (that's in the model, not the CLI)

### Proxy Integration
The proxy server is a lightweight [Hono](https://hono.dev/) app running on Fastify that:
1. Listens on `127.0.0.1:<port>` (default 5529)
2. Exposes the exact same API surface as `api.anthropic.com` (`/v1/messages`, `/v1/models`, `/v1/messages/count_tokens`)
3. Routes requests to the configured provider based on model name matching
4. Handles protocol conversion between Anthropic Messages, OpenAI Chat, and OpenAI Responses formats
5. Answers trivial probes (HEAD/OPTIONS, health checks) locally to save latency

### Android Compatibility
On Android (Termux), binaries compiled with `bun build --compile --target=bun-linux-arm64` produce ELF shared objects (PIE) linked against glibc. Since Android uses Bionic libc, the `install-jxproxy-termux.sh` script:
1. Installs `glibc-runner` from the Termux glibc repository (provides `ld-linux-aarch64.so.1` loader + glibc shared libraries)
2. Runs all jxproxy binaries through the glibc loader with `LD_PRELOAD` unset (Termux's `libtermux-exec-ld-preload.so` is compiled for Bionic, not glibc)
3. Renames any existing `/usr/bin/claude` to `claude-official` to prevent conflicts with the official launcher
4. Writes clean `.bashrc` and `.profile` — no stale aliases, no duplicate PATH entries

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

This project builds on the work of several prior efforts:
- **[free-code](https://github.com/freecodexyz/free-code)** — Source-level Claude Code fork with telemetry and guardrail modifications
- **[free-claude-code](https://github.com/Alishahryar1/free-claude-code)** — Python proxy server for routing Claude Code API calls
- **[claude-code-android](https://github.com/ferrumclaudepilgrim/claude-code-android)** — Android Termux compatibility via ELF patching

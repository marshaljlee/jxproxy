# jxproxy — Architecture

## System Overview

jxproxy is a self-contained software stack combining a modified Claude Code CLI and an embedded proxy server. All API traffic is intercepted by the proxy, giving users complete control over AI model routing. The CLI has telemetry stripped, guardrails removed, and 54 experimental features unlocked.

```
┌──────────────────────────────────────────────────────────────────┐
│                        jxproxy Launcher                          │
│  (scripts/jxproxy-launcher.sh)                                   │
│                                                                  │
│  ┌──────────────────────────────┐    ┌──────────────────────────┐│
│  │     Modified Claude CLI       │    │    Proxy Server          ││
│  │     (src/ — compiled binary)  │    │    (proxy/server.ts)     ││
│  │                              │    │                          ││
│  │  ANTHROPIC_BASE_URL ────────►│───►│  POST /v1/messages       ││
│  │  is set to localhost:${PORT}  │    │  POST /v1/messages/      ││
│  │                              │    │        count_tokens      ││
│  │  • No telemetry              │    │  GET  /v1/models         ││
│  │  • No guardrails             │    │  GET  /health            ││
│  │  • 55 experimental features  │    │                          ││
│  └──────────────────────────────┘    │  ┌────────────────────┐   ││
│                                       │  │   Model Router     │   ││
│                                       │  │  ┌──────────────┐  │   ││
│                                       │  │  │ Anthropic    │  │   ││
│                                       │  │  │ Direct       │  │   ││
│                                       │  │  ├──────────────┤  │   ││
│                                       │  │  │ OpenRouter   │  │   ││
│                                       │  │  ├──────────────┤  │   ││
│                                       │  │  │ OpenAI Codex │  │   ││
│                                       │  │  ├──────────────┤  │   ││
│                                       │  │  │ Local LLMs   │  │   ││
│                                       │  │  └──────────────┘  │   ││
│                                       │  └────────────────────┘   ││
│                                       └──────────────────────────┘│
└──────────────────────────────────────────────────────────────────┘
```

## Component Breakdown

### 1. Modified Claude Code CLI (`src/`)

The CLI is based on the **free-code** source fork, which is itself based on the publicly-exposed Claude Code TypeScript source.

**Modifications applied (via patches/):**

| Patch | What it does |
|-------|-------------|
| `0001-strip-telemetry.patch` | Stubs OpenTelemetry, Sentry, GrowthBook, and all custom event logging. Session fingerprinting returns a static ID. |
| `0002-remove-guardrails.patch` | Removes hardcoded refusal patterns, "cyber risk" instruction blocks injected into system prompts, and managed-settings polling. |
| `0003-proxy-routing.patch` | Changes the default `ANTHROPIC_BASE_URL` from `https://api.anthropic.com` to `http://127.0.0.1:5529`. The auth token is set by the launcher via `ANTHROPIC_AUTH_TOKEN=jxproxy`. |

**Build process** (`scripts/build.ts`):
- Input: `src/entrypoints/cli.tsx` + 55 feature flags
- Tool: `bun build --compile --target=bun`
- Output: Single standalone binary (`dist/jxproxy`)
- No runtime dependencies beyond the OS dynamic linker
- Feature flags are compile-time `bun:bundle` switches
- Telemetry SDK packages are `--external` (never bundled)
- Compile-time defines inject version, build time, and kill-switch env vars

### 2. Proxy Server (`proxy/server.ts`)

A lightweight HTTP server built on `Bun.serve()` with zero external dependencies.

**API Surface:**

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/messages` | POST | Anthropic Messages-compatible streaming proxy |
| `/v1/messages` | HEAD/OPTIONS | 204 compatibility probe |
| `/v1/messages/count_tokens` | POST | Local token counting (heuristic) |
| `/v1/models` | GET | Model listing with configured tiers |
| `/health` | GET | Health check |
| `/stop` | POST | Stop active sessions |
| `/` | GET | Health check (alias) |

**Provider routing** (configurable via `JXPROXY_PROVIDER`):

| Provider | Protocol | How it works |
|----------|----------|-------------|
| `direct` | Anthropic Messages | Passes requests to `api.anthropic.com` with your API key |
| `openrouter` | OpenAI Chat → Anthropic SSE | Converts to OpenAI Chat format, routes via OpenRouter, converts SSE back |
| `opencode-zen` | OpenAI Chat | Routes to `opencode.ai/zen/v1`, uses `OPENCODE_API_KEY` |
| `opencode-go` | OpenAI Chat | Routes to `opencode.ai/zen/go/v1`, shares `OPENCODE_API_KEY` |
| `openai` | OpenAI Chat | Translates to OpenAI Chat format → Chat Completions |
| `local` | OpenAI Chat | Routes to a local LLM endpoint (Ollama, LM Studio, llama.cpp) |

**Model routing** resolves incoming model names:
- Direct provider refs (e.g., `openrouter/anthropic/claude-sonnet-5`) are passed through
- Claude model tier matching: name contains `opus`/`sonnet`/`haiku` → mapped to tier override
- Fallback to `MODEL` env var

**Protocol conversion** (`openAIToAnthropicSSE`):
- OpenAI Chat Completion chunks → Anthropic SSE events (`content_block_start`, `content_block_delta`, `content_block_stop`, `message_start`, `message_delta`, `message_stop`)
- Handles tool calls, reasoning, finish reasons
- Usage token mapping for billing display

### 3. Launcher System

**Primary launcher** (`scripts/jxproxy-launcher.sh`):
- Manages proxy server lifecycle (start, stop, ensure running)
- Proxy PID file at `~/.jxproxy/proxy.pid`
- Health-check loop before launching CLI
- Graceful rollback on proxy startup failure
- Sets `ANTHROPIC_AUTH_TOKEN=jxproxy` so Claude Code authenticates with the proxy
- Passes `$@` through to the CLI binary
- Sets `ANTHROPIC_BASE_URL`, auto-compact window, gateway model discovery

**Windows launcher** (generated by `install.ps1`):
- Batch file at `%USERPROFILE%\.local\bin\jxproxy.bat`
- Starts proxy in background via `start /b`
- Polling health-check loop
- Sets same environment variables

## Cross-Platform Support

| Platform | Binary Type | Special Handling |
|----------|-------------|-----------------|
| macOS (arm64) | Native mach-o | Standard `bun build --compile` |
| macOS (x64) | Native mach-o | Standard `bun build --compile` |
| Linux (arm64/x64) | Native ELF | Standard `bun build --compile` |
| Android (Termux) aarch64 | ELF → ELF-patched | `patchelf --set-interpreter` to Termux glibc-runner |
| Android (Termux) x86_64 | ELF → ELF-patched | Same — `patchelf` with `ld-linux-x86-64.so.2` |
| Windows (x64) | PE | `bun build --compile --target=bun-windows-x64` |
| Windows (ARM64) | PE | `bun build --compile --target=bun-windows-arm64` (Bun 1.2+) |
| iOS (a-Shell) | ELF (via iSH) | Linux arm64 binary in iSH Linux environment |

### Android ELF Patching

The Termux installer (`installers/install-android.sh`) follows the same approach as `claude-code-android`:

1. **Dependencies**: `glibc-runner`, `patchelf-glibc` from Termux's glibc repository
2. **Binary acquisition**: Builds or downloads the linux-arm64 binary
3. **ELF patching**: `LD_PRELOAD='' patchelf --set-interpreter $PREFIX/glibc/lib/ld-linux-aarch64.so.1`
4. **Crash resilience**: Wrapper performs pre-flight smoke test (`--init-only`, 25s timeout); if crash detected, binary is blocklisted and rollback to previous version
5. **Version retention**: Keeps N and N-1 versions; auto-cleans older ones
6. **LD_PRELOAD sanitization**: Unset before exec to prevent libtermux-exec conflicts

## Telemetry Elimination

All outbound telemetry is removed at three levels:

### 1. Source-Level (patches/)
- OpenTelemetry: `withApiTracing` becomes a no-op passthrough. Exporter packages are never bundled.
- Sentry: `initSentry` and `captureError` become empty functions. No DSN, no initialization.
- GrowthBook: Feature flag evaluation kept local for runtime gates. Reporting callback (`trackingCallback`) is removed.
- Custom events: `recordEvent`, `trackMetric`, `logAction` become no-ops. The event queue and flush mechanism are dead-code-eliminated.
- Session/Device ID: Returns static "jxproxy-no-device-id" — no fingerprinting.

### 2. Build-Level (scripts/build.ts)
- `--external` for all `@opentelemetry/*`, `@sentry/*`, `@growthbook/*` packages — they are never included in the binary.
- Compile-time defines set kill-switch env vars: `CLAUDE_CODE_DISABLE_TELEMETRY=true`, `OTEL_SDK_DISABLED=true`, `SENTRY_DSN=""`, `DO_NOT_TRACK="1"`.

### 3. Runtime-Level (launcher)
- Environment sanitization: the launcher strips any `ANTHROPIC_*` credentials that would bypass the proxy.
- Proxy only listens on `127.0.0.1` — no unauthorized external access.

## Guardrail Removal

The extra prompt-level restrictions added by upstream are removed:

1. **Hardcoded refusal patterns**: The array of regex refusal patterns is removed from the conversation loop. The binary no longer pre-filters responses against a curated blocklist.
2. **"Cyber risk" instruction blocks**: The injected preamble ("Do not assist with generating malware...") is removed from system prompt assembly.
3. **Managed-settings overlays**: `fetchManagedSettings()` returns an empty array — no server-pushed policy blocks are retrieved or applied.

The model's own safety training (in the model weights, not the CLI) is unaffected.

## Feature Flag Architecture

Upstream Claude Code ships 88 feature flags gated behind `bun:bundle` compile-time switches. jxproxy enables all 55 that compile cleanly.

**How they work at compile time:**
```typescript
// In the source code:
if (MACRO.FEATURE_ULTRAPLAN) {
  // Ultrplan code path — included in binary
}

// At build time, bun replaces MACRO.FEATURE_* with true or false
// Dead-code elimination removes the false branches
```

**The build script** (`scripts/build.ts`) generates the feature flag array and passes each as `--feature=<name>` to Bun's bundler.

## Developer Workflow

```bash
# First time setup
git clone https://github.com/marshaljlee/jxproxy.git
cd jxproxy
bun run bootstrap    # Fetch free-code source + apply patches
bun run build        # Build the CLI + proxy binaries

# Development cycle
bun run build:dev    # Dev build (debug symbols, faster compile)
./dist/jxproxy-dev   # Test the binary
# Edit patches in patches/ if source changes are needed
bun run build        # Rebuild

# Adding a reconstruction
# 1. Write the missing file into src/
# 2. Test it builds with the associated feature flag
# 3. Update docs/FEATURES.md
# 4. Create a new patch if needed
```

# Changelog

## 0.1.0 (2026-07-01)

Initial release.

### Features
- Proxy-routed API connections — all Anthropic traffic goes through the embedded proxy
- Telemetry stripped — OpenTelemetry, Sentry, GrowthBook, all custom events removed
- Guardrails removed — no hardcoded refusal patterns, no injected "cyber risk" blocks, no managed-settings overlays
- 55 experimental features enabled — all compile-clean feature flags active
- Single binary build — `bun build --compile` produces a standalone executable
- Embedded proxy server — lightweight HTTP proxy in TypeScript, zero external deps
- Model routing — direct Anthropic, OpenRouter, OpenAI-compatible, local LLMs
- Protocol conversion — OpenAI Chat ↔ Anthropic Messages SSE
- Cross-platform: macOS (arm64/x64), Linux (arm64/x64), Windows (x64), Android (Termux)
- Launcher system — starts proxy + CLI, manages lifecycle, health checks
- Patches system — modular patch files for telemetry, guardrails, proxy routing

### Installers
- macOS/Linux: `install.sh`
- Android/Termux: `installers/install-android.sh` (ELF patching, crash rollback, auto-update wrapper)
- Windows: `installers/install.ps1` (PowerShell)

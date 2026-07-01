# jxproxy — Agent Instructions

## Project Identity
This is a downstream fork of Claude Code that:
- Strips all telemetry (no callbacks home)
- Removes all guardrails/injected system prompts
- Enables 54 experimental features via compile-time flags
- Routes all API traffic through an embedded proxy server
- Ships as a single cross-platform binary

## Key Principles
1. **Zero callbacks home** — NO telemetry, NO crash reports, NO analytics, NO session fingerprints. Ever.
2. **Source-level modifications** — changes are made via patches applied to the base source, not runtime hacks.
3. **Proxy-first** — the proxy is the default path. `ANTHROPIC_BASE_URL` always points to localhost.
4. **Cross-platform** — macOS, Linux, Android (Termux), Windows, iOS (experimental).
5. **One binary** — `bun build --compile` produces a single deployable binary.

## Source Structure
- `src/` — Modified Claude Code source (fetched from upstream, patches applied)
- `proxy/` — Embedded TypeScript proxy server
- `scripts/` — Build tooling and launchers
- `installers/` — Platform-specific install scripts
- `patches/` — Git-style patch files applied to base source

## Build Pipeline
```
bun run bootstrap   # Fetch free-code base source + install deps
bun run patch       # Apply jxproxy patches
bun run build       # Build modified CLI binary
bun run build:proxy # Build proxy server binary
```

## Branch Strategy
- `main` — Stable release branch
- `develop` — Integration branch
- `feature/*` — Individual feature work

## Verification
Before commits: verify the binary builds, the proxy starts, and NO outbound connections are made to Anthropic telemetry endpoints.

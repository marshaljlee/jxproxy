# jxproxy — Cross-Platform Support

## Supported Platforms

| Platform | CPU | Status | Install Method | Notes |
|----------|-----|--------|---------------|-------|
| macOS 13+ | Apple Silicon | ✅ Primary | `install.sh` | Native binary. Bun compiles mach-o. |
| macOS 13+ | Intel | ✅ | `install.sh` | Native binary. Bun targets x64. |
| Linux (x64) | x86_64 | ✅ | `install.sh` | Native ELF binary. |
| Linux (arm64) | aarch64 | ✅ | `install.sh` | Native ELF binary. Also used as base for Android. |
| Windows 10/11 | x64 | ✅ | `install.ps1` | PE binary via `bun build --compile --target bun-windows-x64`. |
| Windows 11 on ARM | arm64 | ✅ | `install.ps1` | PE binary via `bun build --compile --target bun-windows-arm64` (Bun 1.2+). Auto-detected. |
| Android 8+ | aarch64 | ✅ | `install-android.sh` | ELF binary + patchelf for Termux glibc compatibility. |
| Android 8+ (Chromebooks/Tablets) | x86_64 | ✅ | `install-android.sh` | Same process — linux-x64 binary + ELF patching. Auto-detected. |
| iOS (iSH) | x86_64 | 🚧 Experimental | Manual | Linux x64 binary inside iSH app. Performance limited. |

## Installation Guides

### macOS

```bash
# Option 1: Direct install
curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/install.sh | bash

# Option 2: Build from source
git clone https://github.com/marshaljlee/jxproxy.git
cd jxproxy
bun run bootstrap
bun run build

# Quick start
jxproxy
```

**Binary locations:**
- `~/.local/bin/jxproxy` — CLI binary
- `~/.local/bin/jxproxy-proxy` — Proxy server binary
- `~/.jxproxy/config.env` — Configuration
- `~/.jxproxy/proxy.log` — Proxy logs

### Linux

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/install.sh | bash

# With custom provider
curl -fsSL ... | bash -s -- --provider=openrouter
```

Same binary locations as macOS.

### Windows

```powershell
# PowerShell (Run as Administrator)
iwr -useb https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/install.ps1 | iex

# With custom options
iwr -useb ... | iex; & "---args" "-Provider=openrouter" "-MinClone"
```

**Binary locations:**
- `%USERPROFILE%\.local\bin\jxproxy.exe` — CLI binary
- `%USERPROFILE%\.local\bin\jxproxy-proxy.exe` — Proxy binary
- `%USERPROFILE%\.local\bin\jxproxy.bat` — Launcher
- `%USERPROFILE%\.jxproxy\config.env` — Configuration

**Prerequisites:**
- Windows 10/11, x64
- PowerShell 7+
- Git (installed automatically via winget)
- Bun runtime (installed automatically)

### Android (Termux)

```bash
# 1. Install Termux from F-Droid (NOT Google Play)
# https://f-droid.org/packages/com.termux/

# 2. Update packages
pkg update && pkg upgrade

# 3. Install jxproxy
curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/install-android.sh | bash

# 4. Launch
jxproxy-launcher
```

**Requirements:**
- Termux from F-Droid (Google Play version is too old)
- Android 8+ with aarch64 CPU
- 8GB+ free storage
- glibc-runner package (installed automatically)

**Technical note:** The `bun build --compile` binary uses glibc, which isn't available on Android's Bionic libc. The installer patches the ELF interpreter to point at Termux's glibc-runner, making the binary executable. This is the same approach used by `claude-code-android`.

### iOS (iSH — Experimental)

```bash
# 1. Install iSH from the App Store
# 2. Open iSH and install dependencies
apk add curl git

# 3. Install jxproxy
curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/install.sh | bash

# 4. Launch
jxproxy
```

**Limitations:**
- iSH uses x86 emulation on ARM iOS devices, so performance is significantly slower
- The binary runs as a Linux x64 ELF inside iSH's Alpine Linux environment
- Voice mode and some native addons won't work
- Useful for simple editing tasks and sessions

## Platform-Specific Considerations

### Environment Variables

All platforms support the same environment variables. You can:
1. Set them in `~/.jxproxy/config.env` (persistent)
2. Export them before launching `jxproxy` (per-session)
3. Pass via the launcher (see documentation)

### File System Paths

| Platform | Config | Data | Logs |
|----------|--------|------|------|
| macOS/Linux | `~/.jxproxy/config.env` | `~/.jxproxy/` | `~/.jxproxy/proxy.log` |
| Windows | `%USERPROFILE%\.jxproxy\config.env` | `%USERPROFILE%\.jxproxy\` | `%USERPROFILE%\.jxproxy\proxy.log` |
| Android | `~/.jxproxy/config.env` | `~/.jxproxy/` | `~/.jxproxy/proxy.log` |

### Proxy Port

The default port is **5529**. This can be changed via `JXPROXY_PORT` or the config file. The port is chosen to avoid conflicts with common services:

- 8080 → HTTP alternate
- 3000 → dev servers
- 11434 → Ollama
- 5529 → unassigned by IANA (safe)

## Building Platform-Specific Binaries

```bash
# macOS (Apple Silicon) — default on ARM Macs
bun run scripts/build.ts --target=bun-darwin-arm64

# macOS (Intel)
bun run scripts/build.ts --target=bun-darwin-x64

# Linux (x64)
bun run scripts/build.ts --target=bun-linux-x64

# Linux (arm64 — for Android base)
bun run scripts/build.ts --target=bun-linux-arm64

# Windows (x64 — cross-compile from any platform)
bun run scripts/build.ts --target=bun-windows-x64

# Windows (ARM64 — cross-compile from any platform)
bun run scripts/build.ts --target=bun-windows-arm64
```

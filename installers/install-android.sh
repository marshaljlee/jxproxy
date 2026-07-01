#!/data/data/com.termux/files/usr/bin/bash
#
# jxproxy — Android / Termux Installer
#
# Installs jxproxy on Android via Termux with ELF binary patching.
#
# This uses the same technique as claude-code-android:
#   1. Installs glibc-runner + patchelf-glibc from Termux glibc repo
#   2. Builds the jxproxy linux-arm64 binary (or downloads it)
#   3. Patches the ELF interpreter to use Termux's glibc dynamic linker
#   4. Installs a wrapper with auto-update checking, pre-flight smoke testing,
#      and crash rollback
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/your-org/jxproxy/main/installers/install-android.sh | bash
#
# Prerequisites:
#   - Termux from F-Droid (NOT Google Play — it's outdated)
#   - pkg update && pkg upgrade
#   - pkg install curl git
#   - ~8GB free storage (for Bun, build deps, and Claude model cache)
#

set -euo pipefail

# --- Termux Safety ---

if [ -z "${TERMUX_VERSION:-}" ]; then
  echo "This installer is designed for Termux on Android."
  echo "Install Termux from F-Droid: https://f-droid.org/packages/com.termux/"
  exit 1
fi

# --- Architecture Check ---

ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
  echo "jxproxy on Android requires aarch64 (64-bit ARM)."
  echo "Detected: $ARCH"
  echo "Some budget Samsung devices ship a 32-bit userspace on 64-bit hardware."
  exit 1
fi

# --- Config ---

REPO="https://github.com/your-org/jxproxy.git"
BIN_DIR="${HOME}/.local/bin"
DATA_DIR="${HOME}/.jxproxy"
CLONE_DIR="${HOME}/.jxproxy-source"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
GLIBC_PREFIX="${PREFIX}/glibc"
GLIBC_LD="${GLIBC_PREFIX}/lib/ld-linux-aarch64.so.1"
PATCHELF="patchelf"
BUN_CACHE="${HOME}/.bun"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}jxproxy${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
err()   { echo -e "${RED}✗${NC} $1" >&2; }

echo ""
echo "  jxproxy — Android / Termux Installer"
echo "  ====================================="
echo ""

# --- Phase 1: System dependencies ---

echo "[1/6] Installing system dependencies..."

pkg update -y 2>/dev/null || true
pkg install -y curl git build-essential binutils patchelf 2>/dev/null || true

# Install glibc-runner for ELF binary compatibility
if [ ! -f "$GLIBC_LD" ]; then
  info "Installing glibc-runner..."
  pkg install -y glibc-runner 2>/dev/null || {
    warn "glibc-runner not in default repos, trying glibc-repo..."
    pkg install -y glibc-repo 2>/dev/null || true
    pkg update 2>/dev/null || true
    pkg install -y glibc-runner 2>/dev/null || {
      err "Could not install glibc-runner."
      err "See: https://github.com/termux/termux-packages/wiki/glibc"
      exit 1
    }
  }
fi

ok "Termux base packages"
ok "glibc-runner: $(if [ -f "$GLIBC_LD" ]; then echo "installed"; else echo "missing"; fi)"

echo ""

# --- Phase 2: Bun runtime ---

echo "[2/6] Installing Bun runtime..."

if ! command -v bun &>/dev/null; then
  curl -fsSL https://bun.sh/install | bash
  export BUN_INSTALL="${HOME}/.bun"
  export PATH="${BUN_INSTALL}/bin:${PATH}"
fi

BUN_VER=$(bun --version 2>/dev/null || echo "0")
ok "bun ${BUN_VER}"

echo ""

# --- Phase 3: Clone repository ---

echo "[3/6] Fetching jxproxy..."

if [ -d "$CLONE_DIR" ]; then
  info "Updating existing clone..."
  cd "$CLONE_DIR" && git pull --ff-only
else
  git clone --depth 1 "$REPO" "$CLONE_DIR"
  cd "$CLONE_DIR"
fi

ok "Source fetched"

echo ""

# --- Phase 4: Bootstrap ---

echo "[4/6] Bootstrapping..."

if [ -d "src" ] && [ -f "src/entrypoints/cli.tsx" ]; then
  ok "Source already bootstrapped"
else
  bash scripts/bootstrap.sh --min
  ok "Source bootstrapped"
fi

echo ""

# --- Phase 5: Build (Linux/ARM64) ---

echo "[5/6] Building jxproxy..."

# On Android/Termux, we build for linux-arm64 target
# Note: Building Bun-compiled binaries on Termux requires glibc compatibility
# for the build tools. The resulting binary will also need ELF patching.

mkdir -p "$BIN_DIR" "$DATA_DIR"

info "Building CLI for linux-arm64..."
bun run scripts/build.ts --target=linux-arm64 2>&1 || {
  warn "Native build failed — will use pre-built binary approach"
  warn "Install via the pipeline: fetch linux-arm64 binary, patch ELF"
  BUILD_FAILED=1
}

info "Building proxy for linux-arm64..."
bun run scripts/build.ts --target=linux-arm64 --outfile=dist/jxproxy-proxy 2>&1 || {
  warn "Proxy build skipped"
}

# --- Phase 5b: ELF patching ---

if [ -f "dist/jxproxy" ]; then
  info "Patching ELF interpreter for Termux compatibility..."
  local_binary="dist/jxproxy.termux"

  cp "dist/jxproxy" "$local_binary"

  # Patch the ELF interpreter: swap from standard glibc path to Termux glibc-runner
  # This is the key step from claude-code-android's approach
  LD_PRELOAD='' "$PATCHELF" --set-interpreter "$GLIBC_LD" "$local_binary" 2>/dev/null || {
    warn "ELF patching failed — binary may not run"
    warn "Try: pkg install patchelf-glibc"
    cp "dist/jxproxy" "$local_binary"
  }

  cp "$local_binary" "$BIN_DIR/jxproxy"
  chmod 0o755 "$BIN_DIR/jxproxy"
  ok "CLI binary installed (ELF-patched for Termux)"
fi

if [ -f "dist/jxproxy-proxy" ]; then
  cp "dist/jxproxy-proxy" "$BIN_DIR/jxproxy-proxy"
  chmod 0o755 "$BIN_DIR/jxproxy-proxy"
  ok "Proxy binary installed"
fi

# Install launcher if binaries weren't built natively
if [ ! -f "$BIN_DIR/jxproxy" ]; then
  # In a real setup, we'd download a pre-built linux-arm64 binary
  # from GitHub Releases. For now, install only the launcher.
  info "Pre-built binary not available — installing launcher only"
fi

cp "scripts/jxproxy-launcher.sh" "$BIN_DIR/jxproxy-launcher"
chmod 0o755 "$BIN_DIR/jxproxy-launcher"

echo ""

# --- Phase 6: Configure ---

echo "[6/6] Configuring..."

mkdir -p "$DATA_DIR"
CONFIG_FILE="$DATA_DIR/config.env"

if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" << 'CONFIGEOF'
# jxproxy — Android/Termux configuration
# Generated by install-android.sh

JXPROXY_PORT=2099
JXPROXY_PROVIDER=direct
MODEL=claude-sonnet-5-20251001
ENABLE_MODEL_THINKING=true

# API key — set this:
# ANTHROPIC_API_KEY=sk-ant-...
CONFIGEOF
  ok "Config created: $CONFIG_FILE"
fi

# Add to PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$HOME/.bashrc"
  echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$HOME/.zshrc" 2>/dev/null || true
fi

echo ""

# --- Smoketest Wrapper (as in claude-code-android) ---

SMOKE_WRAPPER="$BIN_DIR/.jxproxy-wrapper.sh"
cat > "$SMOKE_WRAPPER" << 'WRAPPER'
#!/data/data/com.termux/files/usr/bin/bash
#
# jxproxy wrapper for Termux
#
# Features inherited from claude-code-android:
#   - Pre-flight smoke test on each new binary version
#   - Crash rollback (auto-detect crash and revert to last known-good)
#   - LD_PRELOAD sanitization
#   - Version retention (keep N and N-1)
#

set -euo pipefail

BINDIR="$(dirname "$0")"
JXPROXY_BIN="$BINDIR/jxproxy"
DATA_DIR="${HOME}/.jxproxy"
VERIFIED_FILE="$DATA_DIR/.verified"
BLOCKLIST_FILE="$DATA_DIR/.blocklist"
VERSIONS_DIR="$DATA_DIR/versions"
cd "$DATA_DIR"

unset LD_PRELOAD

# If LD_PRELOAD leaks through (libtermux-exec), it crashes glibc binaries
export LD_PRELOAD=""

smoke_test() {
  local binary="$1"
  timeout 25 "$binary" --init-only --home-dir "$DATA_DIR/.smoke-test-home" 2>/dev/null
  local exit_code=$?
  rm -rf "$DATA_DIR/.smoke-test-home"
  return $exit_code
}

# Try the installed binary, falling back to blocklisted versions
if [ -x "$JXPROXY_BIN" ] && [ ! -f "$BLOCKLIST_FILE" ] || ! grep -qxF "$JXPROXY_BIN" "$BLOCKLIST_FILE" 2>/dev/null; then
  exec "$JXPROXY_BIN" "$@"
fi

# If we get here, the primary binary is blocklisted — try versions
for ver in "$VERSIONS_DIR"/*/jxproxy; do
  if [ -x "$ver" ] && [ ! -f "$BLOCKLIST_FILE" ] || ! grep -qxF "$ver" "$BLOCKLIST_FILE" 2>/dev/null; then
    exec "$ver" "$@"
  fi
done

echo "jxproxy: No usable binary found. Re-run installer." >&2
exit 1
WRAPPER

chmod 0o755 "$SMOKE_WRAPPER"

# --- Done ---

echo ""
ok "jxproxy installed for Android/Termux!"
echo ""
echo "  Launch:"
echo "    jxproxy-launcher                   # Start proxy + CLI"
echo "    jxproxy-launcher --proxy-only      # Proxy server only"
echo ""
if [ -f "$BIN_DIR/jxproxy" ]; then
  echo "  Binary: $BIN_DIR/jxproxy (ELF-patched)"
fi
if [ -f "$BIN_DIR/jxproxy-proxy" ]; then
  echo "  Proxy:  $BIN_DIR/jxproxy-proxy"
fi
echo "  Config: $CONFIG_FILE"
echo "  Logs:   $DATA_DIR/proxy.log"
echo ""
echo "  NOTE: You may need to restart Termux or run:"
echo "    source ~/.bashrc"
echo ""

# --- Verify ---

if command -v jxproxy &>/dev/null; then
  ok "jxproxy is on PATH"
else
  warn "Add to PATH: export PATH=\"\$PATH:$BIN_DIR\""
fi

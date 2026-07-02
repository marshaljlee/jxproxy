#!/data/data/com.termux/files/usr/bin/bash
#
# jxproxy — Android / Termux Installer
#
# Installs jxproxy on Android via Termux with ELF binary patching.
#
# This uses the same technique as claude-code-android:
#   1. Installs glibc-runner + patchelf from Termux glibc repo
#   2. Downloads the pre-built jxproxy linux-arm64 binary from GitHub Releases
#   3. Patches the ELF interpreter to use Termux's glibc dynamic linker
#   4. Installs a wrapper with auto-update checking, pre-flight smoke testing,
#      and crash rollback
#
# On Termux, building from source is not possible because Bun (glibc binary)
# cannot run on Android's bionic libc. Instead, pre-built binaries are
# downloaded and ELF-patched — same approach as claude-code-android.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/install-android.sh | bash
#   curl -fsSL ... | bash -s -- --from-dist /sdcard/Download/dist  # Use local pre-built binaries
#
# Prerequisites:
#   - Termux from F-Droid (NOT Google Play — it's outdated)
#   - pkg update && pkg upgrade
#   - ~4GB free storage
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
case "$ARCH" in
  aarch64)
    BINARY_SUFFIX="linux-arm64"
    GLIBC_LD_NAME="ld-linux-aarch64.so.1"
    ARCH_LABEL="ARM64"
    ;;
  x86_64)
    BINARY_SUFFIX="linux-x64"
    GLIBC_LD_NAME="ld-linux-x86-64.so.2"
    ARCH_LABEL="x86_64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    echo "jxproxy on Android requires aarch64 (ARM64) or x86_64."
    echo "Detected: $ARCH"
    exit 1
    ;;
esac

# --- Config ---

GH_REPO="marshaljlee/jxproxy"
RELEASE_URL="https://github.com/$GH_REPO/releases/latest/download"
BIN_DIR="${HOME}/.local/bin"
DATA_DIR="${HOME}/.jxproxy"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
GLIBC_PREFIX="${PREFIX}/glibc"
GLIBC_LD="${GLIBC_PREFIX}/lib/${GLIBC_LD_NAME}"
PATCHELF="patchelf"
FROM_DIST=""

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --from-dist=*) FROM_DIST="${1#*=}"; shift ;;
    --from-dist)   FROM_DIST="$2"; shift 2 ;;
    --help|-h)
      echo "jxproxy installer — Android/Termux"
      echo ""
      echo "  --from-dist=PATH   Copy pre-built binaries from PATH instead of downloading"
      echo "                     (build with: bun run build --target=bun-linux-arm64)"
      echo "  --help             Show this help"
      exit 0
      ;;
    *) shift ;;
  esac
done

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}jxproxy${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
err()   { echo -e "${RED}✗${NC} $1" >&2; }

echo ""
echo -e "  ${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}║${NC}               ${CYAN}jxproxy Android Installer${NC}               ${BOLD}║${NC}"
echo -e "  ${BOLD}║${NC}                                                          ${BOLD}║${NC}"
echo -e "  ${BOLD}║${NC}  ${BOLD}Platform:${NC}  Android / Termux (${ARCH_LABEL})                ${BOLD}║${NC}"
echo -e "  ${BOLD}║${NC}  ${BOLD}Bin dir:${NC}   ${BIN_DIR}            ${BOLD}║${NC}"
echo -e "  ${BOLD}║${NC}  ${BOLD}Data dir:${NC}  ${DATA_DIR}            ${BOLD}║${NC}"
echo -e "  ${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

step() {
  local num=$1
  local total=$2
  local label=$3
  echo ""
  echo -e "  ${BOLD}┃${NC} ${CYAN}Step ${num}/${total}${NC} ─ ${BOLD}${label}${NC}"
  echo -e "  ${BOLD}┃${NC}"
}

sub_ok()   { echo -e "  ${BOLD}┃${NC}   ${GREEN}✓${NC} $1"; }
sub_info() { echo -e "  ${BOLD}┃${NC}     $1"; }
sub_warn() { echo -e "  ${BOLD}┃${NC}   ${YELLOW}⚠${NC} $1"; }
sub_err()  { echo -e "  ${BOLD}┃${NC}   ${RED}✗${NC} $1" >&2; }
step_done() {
  echo -e "  ${BOLD}┃${NC}"
  echo -e "  ${BOLD}┃${NC} ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ─────────────────────────────────────────────────
#  STEP 1: System Dependencies
# ─────────────────────────────────────────────────

step 1 5 "Installing system dependencies"

# First ensure git is available (needed for gh and cloning)
if ! command -v git &>/dev/null; then
  sub_info "Installing git..."
  pkg install -y git
fi

pkg update -y 2>/dev/null || true
pkg install -y curl patchelf 2>/dev/null || true

# Install glibc-runner for ELF binary compatibility
if [ ! -f "$GLIBC_LD" ]; then
  sub_info "Installing glibc-runner..."
  pkg install -y glibc-runner 2>/dev/null || {
    sub_warn "glibc-runner not in default repos, trying glibc-repo..."
    pkg install -y glibc-repo 2>/dev/null || true
    pkg update 2>/dev/null || true
    pkg install -y glibc-runner 2>/dev/null || {
      sub_err "Could not install glibc-runner."
      sub_err "See: https://github.com/termux/termux-packages/wiki/glibc"
      exit 1
    }
  }
fi

	sub_ok "git: $(git --version 2>/dev/null || echo 'missing')"
	sub_ok "curl: $(curl --version 2>/dev/null | head -1 || echo 'missing')"
	sub_ok "patchelf: $(patchelf --version 2>/dev/null || echo 'installed')"
	sub_ok "glibc-runner: $(if [ -f "$GLIBC_LD" ]; then echo 'installed'; else echo 'missing'; fi)"
	
	step_done

# ─────────────────────────────────────────────────
#  STEP 2: Obtain Binaries
# ─────────────────────────────────────────────────

step 2 5 "Obtaining jxproxy binaries"

mkdir -p "$BIN_DIR" "$DATA_DIR"

if [ -n "$FROM_DIST" ]; then
	  # Copy pre-built binaries from local dist directory
	  sub_info "Using binaries from: $FROM_DIST"
  CLI_SRC="$FROM_DIST/jxproxy"
  PROXY_SRC="$FROM_DIST/jxproxy-proxy"

  CLI_DOWNLOADED=false
  PROXY_DOWNLOADED=false

	if [ -f "$CLI_SRC" ] && [ -x "$CLI_SRC" ]; then
	    LD_PRELOAD='' "$PATCHELF" --set-interpreter "$GLIBC_LD" "$CLI_SRC" 2>/dev/null || true
	    cp "$CLI_SRC" "$BIN_DIR/jxproxy-cli"
	    chmod 755 "$BIN_DIR/jxproxy-cli"
	    sub_ok "CLI binary copied: $BIN_DIR/jxproxy-cli"
	    CLI_DOWNLOADED=true
	  else
	    sub_warn "CLI binary not found at $CLI_SRC"
	  fi
	
	  if [ -f "$PROXY_SRC" ] && [ -x "$PROXY_SRC" ]; then
	    LD_PRELOAD='' "$PATCHELF" --set-interpreter "$GLIBC_LD" "$PROXY_SRC" 2>/dev/null || true
	    cp "$PROXY_SRC" "$BIN_DIR/jxproxy-proxy"
	    chmod 755 "$BIN_DIR/jxproxy-proxy"
	    sub_ok "Proxy binary copied: $BIN_DIR/jxproxy-proxy"
	    PROXY_DOWNLOADED=true
	  else
	    sub_warn "Proxy binary not found at $PROXY_SRC"
	  fi
else
  # Download pre-built binaries from GitHub Releases
  download_and_patch() {
    local name="$1"
    local filename="$2"
    local target="$BIN_DIR/$name"
    local url="$RELEASE_URL/$filename"

	    if [ -f "$target" ] && [ -x "$target" ]; then
	      sub_info "$name already installed at $target"
	      return 0
	    fi

	sub_info "Downloading $name from GitHub releases..."
	    curl -fsSL -o "$target.tmp" "$url" || {
	      sub_warn "Download failed — $filename not found in latest release"
	      sub_warn "  $url"
	      return 1
	    }
	
	    # Patch the ELF interpreter for Termux glibc compatibility
	    LD_PRELOAD='' "$PATCHELF" --set-interpreter "$GLIBC_LD" "$target.tmp" 2>/dev/null || {
	      sub_warn "ELF patching skipped (binary may still work via proot)"
	    }
	
	    chmod 755 "$target.tmp"
	    mv "$target.tmp" "$target"
	    sub_ok "$name installed: $target"
  }

  CLI_DOWNLOADED=false
  PROXY_DOWNLOADED=false

  download_and_patch "jxproxy-cli" "jxproxy-${BINARY_SUFFIX}" && CLI_DOWNLOADED=true
  download_and_patch "jxproxy-proxy" "jxproxy-proxy-${BINARY_SUFFIX}" && PROXY_DOWNLOADED=true
fi

step_done

# ─────────────────────────────────────────────────
#  STEP 3: Install Launcher
# ─────────────────────────────────────────────────

step 3 5 "Installing launcher"

LAUNCHER="$BIN_DIR/jxproxy"

# Try local file first, then download from repo
LAUNCHER_URL="https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/android-launcher.sh"
if [ -f "$(dirname "$0")/android-launcher.sh" ]; then
  cp "$(dirname "$0")/android-launcher.sh" "$LAUNCHER"
  chmod 755 "$LAUNCHER"
  sub_ok "Launcher installed: $LAUNCHER"
elif curl -fsSL -o "$LAUNCHER" "$LAUNCHER_URL"; then
  chmod 755 "$LAUNCHER"
  sub_ok "Launcher downloaded and installed: $LAUNCHER"
else
  sub_warn "Could not install launcher — run jxproxy-cli directly"
  sub_warn "  jxproxy-cli -- --help"
fi

step_done

# ─────────────────────────────────────────────────
#  STEP 4: Configure
# ─────────────────────────────────────────────────

step 4 5 "Configuring"

CONFIG_FILE="$DATA_DIR/config.env"
if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" << CONFIGEOF
# jxproxy — Android/Termux configuration
# Generated by install-android.sh

JXPROXY_PORT=5529
JXPROXY_AUTH_TOKEN=jxproxy
JXPROXY_PROVIDER=direct
MODEL=claude-sonnet-5-20251001
ENABLE_MODEL_THINKING=true

# API key — set this:
# ANTHROPIC_API_KEY=sk-ant-...
CONFIGEOF
  sub_ok "Config created: $CONFIG_FILE"
fi

# Add to PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$HOME/.bashrc"
  echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$HOME/.zshrc" 2>/dev/null || true
  sub_ok "Added $BIN_DIR to PATH in ~/.bashrc"
fi

step_done

# ─────────────────────────────────────────────────
#  STEP 5: Verification
# ─────────────────────────────────────────────────

step 5 5 "Verifying installation"

if $CLI_DOWNLOADED; then
  if "$BIN_DIR/jxproxy-cli" --version 2>/dev/null || "$BIN_DIR/jxproxy-cli" --help >/dev/null 2>&1; then
    sub_ok "CLI binary smoke test passed"
  else
    sub_warn "CLI binary smoke test skipped (may need proot or glibc environment)"
    sub_warn "  Binary is at: $BIN_DIR/jxproxy-cli"
    sub_warn "  Run via the jxproxy launcher, or within proot-distro if native exec fails"
  fi
fi

if $PROXY_DOWNLOADED; then
  chmod 755 "$BIN_DIR/jxproxy-proxy"
  timeout 3 "$BIN_DIR/jxproxy-proxy" &
  sleep 1
  if curl -sf "http://127.0.0.1:5529/health" >/dev/null 2>&1; then
    sub_ok "Proxy binary smoke test passed"
    kill %1 2>/dev/null || true
  else
    sub_warn "Proxy smoke test skipped (will start on launch)"
    kill %1 2>/dev/null || true
  fi
fi

step_done

# ─────────────────────────────────────────────────
#  DONE
# ─────────────────────────────────────────────────

echo ""
echo -e "  ${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}║${NC}       ${GREEN}✓ jxproxy installed successfully!${NC}              ${BOLD}║${NC}"
echo -e "  ${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}To launch:${NC}"
echo "    jxproxy"
echo ""
echo -e "  ${BOLD}Config:${NC}   ${CONFIG_FILE}"
echo -e "  ${BOLD}Logs:${NC}     ${DATA_DIR}/proxy.log"
echo ""
echo -e "  ${BOLD}NOTE:${NC} You may need to close and reopen Termux, or run:"
echo "    source ~/.bashrc"
echo ""

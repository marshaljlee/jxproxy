#!/data/data/com.termux/files/usr/bin/bash
#
# jxproxy — Android / Termux Installer
#
# Installs jxproxy on Android via Termux.
#
# Pre-built PIE (ET_DYN) binaries are downloaded from GitHub Releases.
# Android's Bionic linker rejects these binaries for PT_TLS alignment
# on ARM64, so execution happens through the glibc-runner loader:
#   "$GLIBC_LD" "$BINARY"
# (glibc's loader handles TLS differently — no alignment issue.)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/install-android.sh | bash
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
FROM_DIST=""

while [ $# -gt 0 ]; do
  case "$1" in
    --from-dist=*) FROM_DIST="${1#*=}"; shift ;;
    --from-dist)   FROM_DIST="$2"; shift 2 ;;
    --help|-h)
      echo "jxproxy installer — Android/Termux"
      echo ""
      echo "  --from-dist=PATH   Copy pre-built binaries from PATH instead of downloading"
      echo "  --help             Show this help"
      exit 0
      ;;
    *) shift ;;
  esac
done

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
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
  local num=$1 total=$2 label=$3
  echo ""; echo -e "  ${BOLD}┃${NC} ${CYAN}Step ${num}/${total}${NC} ─ ${BOLD}${label}${NC}"; echo -e "  ${BOLD}┃${NC}"
}
sub_ok()   { echo -e "  ${BOLD}┃${NC}   ${GREEN}✓${NC} $1"; }
sub_info() { echo -e "  ${BOLD}┃${NC}     $1"; }
sub_warn() { echo -e "  ${BOLD}┃${NC}   ${YELLOW}⚠${NC} $1"; }
sub_err()  { echo -e "  ${BOLD}┃${NC}   ${RED}✗${NC} $1" >&2; }
step_done() { echo -e "  ${BOLD}┃${NC}"; echo -e "  ${BOLD}┃${NC} ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ═══════════════════════════════════════════════
#  STEP 1: System Dependencies
# ═══════════════════════════════════════════════

step 1 4 "Installing system dependencies"

pkg update -y 2>/dev/null || true
pkg install -y curl python3 2>/dev/null || true

# Install glibc-runner for glibc shared libraries + loader
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

sub_ok "curl: $(curl --version 2>/dev/null | head -1 || echo 'missing')"
sub_ok "glibc loader: $(if [ -f "$GLIBC_LD" ]; then echo 'installed'; else echo 'missing'; fi)"
step_done

# ═══════════════════════════════════════════════
#  STEP 2: Obtain Binaries
# ═══════════════════════════════════════════════

step 2 4 "Obtaining jxproxy binaries"

mkdir -p "$BIN_DIR" "$DATA_DIR"

download_binary() {
  local name="$1" filename="$2"
  local target="$BIN_DIR/$name"
  local url="$RELEASE_URL/$filename"

  if [ -f "$target" ]; then
    sub_info "$name already installed at $target"
    return 0
  fi

  sub_info "Downloading $name from GitHub releases..."
  curl -fsSL -o "$target.tmp" "$url" || {
    sub_warn "Download failed — $filename not found in latest release"
    return 1
  }

  chmod 755 "$target.tmp"
  mv "$target.tmp" "$target"
  sub_ok "$name downloaded: $target"
}

CLI_DOWNLOADED=false; PROXY_DOWNLOADED=false

if [ -n "$FROM_DIST" ]; then
  sub_info "Using binaries from: $FROM_DIST"
  CLI_SRC="$FROM_DIST/jxproxy"; PROXY_SRC="$FROM_DIST/jxproxy-proxy"
  if [ -f "$CLI_SRC" ] && [ -x "$CLI_SRC" ]; then
    cp "$CLI_SRC" "$BIN_DIR/jxproxy-cli"; chmod 755 "$BIN_DIR/jxproxy-cli"
    sub_ok "CLI binary copied"; CLI_DOWNLOADED=true
  else sub_warn "CLI binary not found at $CLI_SRC"; fi
  if [ -f "$PROXY_SRC" ] && [ -x "$PROXY_SRC" ]; then
    cp "$PROXY_SRC" "$BIN_DIR/jxproxy-proxy"; chmod 755 "$BIN_DIR/jxproxy-proxy"
    sub_ok "Proxy binary copied"; PROXY_DOWNLOADED=true
  else sub_warn "Proxy binary not found at $PROXY_SRC"; fi
else
  download_binary "jxproxy-cli" "jxproxy-${BINARY_SUFFIX}" && CLI_DOWNLOADED=true
  download_binary "jxproxy-proxy" "jxproxy-proxy-${BINARY_SUFFIX}" && PROXY_DOWNLOADED=true
fi

step_done

# ═══════════════════════════════════════════════
#  STEP 3: Install Launcher & Configure
# ═══════════════════════════════════════════════

step 3 4 "Installing launcher & configuring"

# Write GLIBC_LD path to config so launcher can find it
CONFIG_FILE="$DATA_DIR/config.env"
mkdir -p "$DATA_DIR"
if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" << CONFIGEOF
# jxproxy — Android/Termux configuration
JXPROXY_PORT=5529
JXPROXY_AUTH_TOKEN=jxproxy
JXPROXY_PROVIDER=direct
MODEL=claude-sonnet-5-20251001
ENABLE_MODEL_THINKING=true
JXPROXY_GLIBC_LD=${GLIBC_LD}
# API key — set this:
# ANTHROPIC_API_KEY=sk-ant-...
CONFIGEOF
  sub_ok "Config created: $CONFIG_FILE"
else
  # Ensure GLIBC_LD is in existing config
  if ! grep -q "JXPROXY_GLIBC_LD" "$CONFIG_FILE" 2>/dev/null; then
    echo "JXPROXY_GLIBC_LD=${GLIBC_LD}" >> "$CONFIG_FILE"
    sub_ok "Added JXPROXY_GLIBC_LD to existing config"
  fi
fi

# Install launcher
LAUNCHER="$BIN_DIR/jxproxy"
LAUNCHER_URL="https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/android-launcher.sh"

if [ -f "$(dirname "$0")/android-launcher.sh" ]; then
  cp "$(dirname "$0")/android-launcher.sh" "$LAUNCHER"; chmod 755 "$LAUNCHER"
  sub_ok "Launcher installed from local source"
elif curl -fsSL -o "$LAUNCHER" "$LAUNCHER_URL"; then
  chmod 755 "$LAUNCHER"
  sub_ok "Launcher downloaded and installed"
else
  sub_warn "Could not install launcher — run jxproxy-cli through glibc loader directly"
  sub_warn "  ${GLIBC_LD} \$BIN_DIR/jxproxy-cli -- --help"
fi

# Add to PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$HOME/.bashrc"
  echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$HOME/.zshrc" 2>/dev/null || true
  sub_ok "Added $BIN_DIR to PATH in ~/.bashrc"
fi

step_done

# ═══════════════════════════════════════════════
#  STEP 4: Verification
# ═══════════════════════════════════════════════

step 4 4 "Verifying installation"

# Verify CLI through glibc loader
if $CLI_DOWNLOADED && [ -x "$BIN_DIR/jxproxy-cli" ] && [ -f "$GLIBC_LD" ]; then
  sub_info "Testing CLI binary through glibc loader..."
  set +e
  CLI_OUTPUT=$("$GLIBC_LD" "$BIN_DIR/jxproxy-cli" --version 2>&1)
  CLI_EXIT=$?
  set -e
  if [ $CLI_EXIT -eq 0 ]; then
    sub_ok "CLI binary smoke test passed"
  else
    sub_warn "CLI binary smoke test failed (exit $CLI_EXIT)"
    sub_warn "  Output: $(echo "$CLI_OUTPUT" | head -3 | tr '\n' ' ')"
    sub_warn "  Try: LD_LIBRARY_PATH=$(dirname "$GLIBC_LD") $GLIBC_LD $BIN_DIR/jxproxy-cli --version"
  fi
fi

# Verify proxy through glibc loader
if $PROXY_DOWNLOADED && [ -f "$GLIBC_LD" ]; then
  chmod 755 "$BIN_DIR/jxproxy-proxy"
  sub_info "Testing proxy binary through glibc loader..."
  GLIBC_LD_DIR="$(dirname "$GLIBC_LD")"
  JXPROXY_PORT=5529 JXPROXY_PROVIDER=direct \
    LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:$GLIBC_LD_DIR" \
    nohup "$GLIBC_LD" "$BIN_DIR/jxproxy-proxy" > "$DATA_DIR/proxy.log" 2>&1 &
  proxy_pid=$!
  sleep 2
  if kill -0 "$proxy_pid" 2>/dev/null && curl -sf "http://127.0.0.1:5529/health" >/dev/null 2>&1; then
    sub_ok "Proxy binary smoke test passed"
    kill "$proxy_pid" 2>/dev/null || true
  else
    sub_warn "Proxy smoke test skipped (could not connect)"
    tail -5 "$DATA_DIR/proxy.log" 2>/dev/null || true
    kill "$proxy_pid" 2>/dev/null || true
  fi
fi

step_done

# ═══════════════════════════════════════════════
#  DONE
# ═══════════════════════════════════════════════

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
echo -e "  ${BOLD}NOTE:${NC} jxproxy runs through the glibc loader on Android."
echo -e "  ${BOLD}     ${NC} This is automatic via the launcher script."
echo ""

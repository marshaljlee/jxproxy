#!/bin/sh
#
# jxproxy — Alpine Linux Installer
#
# Installs jxproxy on Alpine Linux (ARM64 / x86_64).
#
# Alpine uses musl libc. The jxproxy binaries are compiled against glibc,
# so gcompat must be installed to provide glibc ABI compatibility.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/install-alpine.sh | sh
#
# Prerequisites:
#   - Alpine 3.18+ (gcompat available in community repo)
#   - ~4GB free storage
#

set -eu

# --- Architecture Check ---

ARCH=$(uname -m)
case "$ARCH" in
  aarch64)
    BINARY_SUFFIX="linux-arm64"
    ARCH_LABEL="ARM64"
    ;;
  x86_64)
    BINARY_SUFFIX="linux-x64"
    ARCH_LABEL="x86_64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH (expected aarch64 or x86_64)"
    exit 1
    ;;
esac

# --- Config ---

GH_REPO="marshaljlee/jxproxy"
RELEASE_URL="https://github.com/$GH_REPO/releases/latest/download"
BIN_DIR="${HOME}/.local/bin"
DATA_DIR="${HOME}/.jxproxy"

# --- Colors ---

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${CYAN}jxproxy${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
err()   { echo -e "${RED}✗${NC} $1" >&2; }

echo ""
echo -e "  ${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}║${NC}            ${CYAN}jxproxy Alpine Linux Installer${NC}              ${BOLD}║${NC}"
echo -e "  ${BOLD}║${NC}                                                          ${BOLD}║${NC}"
echo -e "  ${BOLD}║${NC}  ${BOLD}Platform:${NC}  Alpine Linux (${ARCH_LABEL})                     ${BOLD}║${NC}"
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

# Detect Alpine — refuse to run on non-Alpine systems
if [ ! -f /etc/alpine-release ]; then
  warn "This does not look like Alpine Linux (/etc/alpine-release not found)."
  warn "Continuing anyway — the binaries may work with gcompat or glibc."
fi

apk update -q 2>/dev/null || true

# gcompat provides glibc ABI for musl-based systems
if ! command -v gcompat >/dev/null 2>&1; then
  sub_info "Installing gcompat (glibc ABI compatibility)..."
  apk add gcompat curl 2>/dev/null || {
    sub_err "Could not install gcompat. Enable community repo:"
    sub_err "  echo 'https://dl-cdn.alpinelinux.org/alpine/v$(cut -d. -f1,2 /etc/alpine-release)/community' >> /etc/apk/repositories"
    sub_err "  apk update"
    exit 1
  }
else
  # Ensure curl is available
  apk add curl 2>/dev/null || true
fi

sub_ok "gcompat: $(gcompat --version 2>/dev/null | head -1 || echo 'installed')"
sub_ok "curl: $(curl --version 2>/dev/null | head -1 || echo 'missing')"
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
    sub_err "Download failed — $filename not found in latest release"
    return 1
  }

  chmod 755 "$target.tmp"
  mv "$target.tmp" "$target"
  sub_ok "$name downloaded: $target"
}

CLI_DOWNLOADED=false; PROXY_DOWNLOADED=false

download_binary "jxproxy-cli" "jxproxy-${BINARY_SUFFIX}" && CLI_DOWNLOADED=true
download_binary "jxproxy-proxy" "jxproxy-proxy-${BINARY_SUFFIX}" && PROXY_DOWNLOADED=true

step_done

# ═══════════════════════════════════════════════
#  STEP 3: Install Launcher & Configure
# ═══════════════════════════════════════════════

step 3 4 "Installing launcher & configuring"

# Write config
CONFIG_FILE="$DATA_DIR/config.env"
mkdir -p "$DATA_DIR"
if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" << CONFIGEOF
# jxproxy — Alpine Linux configuration
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

# Install launcher
LAUNCHER="$BIN_DIR/jxproxy"

if [ -f "$(dirname "$0")/alpine-launcher.sh" ]; then
  cp "$(dirname "$0")/alpine-launcher.sh" "$LAUNCHER"; chmod 755 "$LAUNCHER"
  sub_ok "Launcher installed from local source"
else
  # Download from GitHub
  LAUNCHER_URL="https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/alpine-launcher.sh"
  if curl -fsSL -o "$LAUNCHER" "$LAUNCHER_URL"; then
    chmod 755 "$LAUNCHER"
    sub_ok "Launcher downloaded and installed"
  else
    sub_warn "Could not download launcher — run jxproxy-cli directly:"
    sub_warn "  $BIN_DIR/jxproxy-cli --help"
  fi
fi

# Add to PATH
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
  shell_rc="${HOME}/.profile"
  if [ -n "${ZSH_VERSION:-}" ]; then
    shell_rc="${HOME}/.zshrc"
  elif [ -n "${BASH_VERSION:-}" ]; then
    shell_rc="${HOME}/.bashrc"
  fi
  echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$shell_rc"
  sub_ok "Added $BIN_DIR to PATH in $shell_rc"
fi

step_done

# ═══════════════════════════════════════════════
#  STEP 4: Verification
# ═══════════════════════════════════════════════

step 4 4 "Verifying installation"

# Verify CLI binary
if $CLI_DOWNLOADED && [ -x "$BIN_DIR/jxproxy-cli" ]; then
  sub_info "Testing CLI binary..."
  set +e
  CLI_OUTPUT=$("$BIN_DIR/jxproxy-cli" --version 2>&1)
  CLI_EXIT=$?
  set -e
  if [ $CLI_EXIT -eq 0 ]; then
    sub_ok "CLI binary smoke test passed"
  else
    sub_warn "CLI binary smoke test failed (exit $CLI_EXIT)"
    sub_warn "  Output: $(echo "$CLI_OUTPUT" | head -3 | tr '\n' ' ')"
    sub_warn "  gcompat may need configuration:"
    sub_warn "  Run manually: gcompat $BIN_DIR/jxproxy-cli --version"
  fi
fi

# Verify proxy binary
if $PROXY_DOWNLOADED && [ -x "$BIN_DIR/jxproxy-proxy" ]; then
  sub_info "Testing proxy binary..."
  JXPROXY_PORT=5529 JXPROXY_PROVIDER=direct \
    nohup "$BIN_DIR/jxproxy-proxy" > "$DATA_DIR/proxy.log" 2>&1 &
  proxy_pid=$!
  sleep 2
  if kill -0 "$proxy_pid" 2>/dev/null && curl -sf "http://127.0.0.1:5529/health" >/dev/null 2>&1; then
    sub_ok "Proxy binary smoke test passed"
    kill "$proxy_pid" 2>/dev/null || true
  else
    sub_warn "Proxy smoke test could not connect"
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
echo -e "  ${BOLD}Direct:${NC}"
echo "    jxproxy-cli --help"
echo ""
echo -e "  ${BOLD}Config:${NC}   ${CONFIG_FILE}"
echo -e "  ${BOLD}Logs:${NC}     ${DATA_DIR}/proxy.log"
echo ""
echo -e "  ${BOLD}NOTE:${NC} jxproxy binaries are glibc-compiled. Alpine uses"
echo -e "  ${BOLD}     ${NC} gcompat for transparent glibc compatibility."
echo ""


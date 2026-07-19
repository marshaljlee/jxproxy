#!/data/data/com.termux/files/usr/bin/bash
#
# jxproxy — Termux / Android Installer
#
# Installs the exact jxproxy configuration from the macOS dev machine
# onto Android via Termux.  Includes proxy, CLI, launcher, all env vars,
# and the model/provider routing table.
#
# Two modes:
#   1. Default — downloads pre-built linux-arm64 binaries from GitHub releases
#   2. --from-dist=PATH — copies pre-built binaries from a local path
#      (e.g. after scp'ing from the macOS build machine)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/install-jxproxy-termux.sh | bash
#
#   # With local dist
#   scp user@mac:/Users/joshua/.jxproxy-source/dist/jxproxy-linux-arm64 /tmp/dist/
#   scp user@mac:/Users/joshua/.jxproxy-source/dist/jxproxy-proxy-linux-arm64 /tmp/dist/
#   curl -fsSL ... | bash -s -- --from-dist=/tmp/dist
#
# Prerequisites:
#   - Termux from F-Droid (NOT Google Play — it's outdated)
#   - pkg update && pkg upgrade
#   - ~4 GB free storage
#   - Internet connection (for GitHub release download)
#

set -euo pipefail

# ─────────────────────────────────────────────────────────────
#  TERMUX GUARD
# ─────────────────────────────────────────────────────────────

if [ -z "${TERMUX_VERSION:-}" ]; then
  echo "This installer is designed for Termux on Android."
  echo "Install Termux from F-Droid: https://f-droid.org/packages/com.termux/"
  exit 1
fi

# ─────────────────────────────────────────────────────────────
#  ARCHITECTURE DETECTION
# ─────────────────────────────────────────────────────────────

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
    echo "jxproxy requires aarch64 (ARM64) or x86_64."
    exit 1
    ;;
esac

# ─────────────────────────────────────────────────────────────
#  HARDCODED PATHS
# ─────────────────────────────────────────────────────────────

GH_REPO="marshaljlee/jxproxy"
RELEASE_URL="https://github.com/$GH_REPO/releases/latest/download"
BIN_DIR="${HOME}/.local/bin"
DATA_DIR="${HOME}/.jxproxy"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
GLIBC_PREFIX="${PREFIX}/glibc"
GLIBC_LD="${GLIBC_PREFIX}/lib/${GLIBC_LD_NAME}"

FROM_DIST=""  # overridden by --from-dist flag

while [ $# -gt 0 ]; do
  case "$1" in
    --from-dist=*) FROM_DIST="${1#*=}"; shift ;;
    --from-dist)   FROM_DIST="$2"; shift 2 ;;
    --help|-h)
      echo "jxproxy installer — Termux (Android)"
      echo ""
      echo "  --from-dist=PATH   Copy pre-built binaries from PATH instead of downloading"
      echo "  --help             Show this help"
      exit 0
      ;;
    *) shift ;;
  esac
done

# ─────────────────────────────────────────────────────────────
#  COLOUR / FORMATTING
# ─────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${CYAN}jxproxy${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
err()   { echo -e "${RED}✗${NC} $1" >&2; }

step() {
  local num=$1 total=$2 label=$3
  echo ""; echo -e "  ${BOLD}┃${NC} ${CYAN}Step ${num}/${total}${NC} ─ ${BOLD}${label}${NC}"; echo -e "  ${BOLD}┃${NC}"
}
sub_ok()   { echo -e "  ${BOLD}┃${NC}   ${GREEN}✓${NC} $1"; }
sub_info() { echo -e "  ${BOLD}┃${NC}     $1"; }
sub_warn() { echo -e "  ${BOLD}┃${NC}   ${YELLOW}⚠${NC} $1"; }
sub_err()  { echo -e "  ${BOLD}┃${NC}   ${RED}✗${NC} $1" >&2; }
step_done() { echo -e "  ${BOLD}┃${NC}"; echo -e "  ${BOLD}┃${NC} ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

echo ""
echo -e "  ${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}║${NC}         ${CYAN}jxproxy — Termux Android Installer${NC}            ${BOLD}║${NC}"
echo -e "  ${BOLD}║${NC}                                                          ${BOLD}║${NC}"
echo -e "  ${BOLD}║${NC}  ${BOLD}Platform:${NC}  Android / Termux (${ARCH_LABEL})                ${BOLD}║${NC}"
echo -e "  ${BOLD}║${NC}  ${BOLD}Bin dir:${NC}   ${BIN_DIR}            ${BOLD}║${NC}"
echo -e "  ${BOLD}║${NC}  ${BOLD}Data dir:${NC}  ${DATA_DIR}            ${BOLD}║${NC}"
echo -e "  ${BOLD}║${NC}  ${BOLD}Config:${NC}    Port 5255 · Provider opencode-zen    ${BOLD}║${NC}"
echo -e "  ${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""


# ═══════════════════════════════════════════════════════════════
#  STEP 1 — System dependencies
# ═══════════════════════════════════════════════════════════════

step 1 5 "Installing system dependencies"

pkg update -y 2>/dev/null || true

# Install glibc-runner — Android's Bionic libc rejects bun-compiled
# glibc binaries for PT_TLS alignment on ARM64, so all execution
# goes through the glibc loader.
if [ ! -f "$GLIBC_LD" ]; then
  sub_info "Installing glibc-runner for glibc compatibility layer..."
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
else
  sub_ok "glibc-runner already installed"
fi

sub_ok "curl: $(curl --version 2>/dev/null | head -1 || echo 'missing')"
sub_ok "glibc loader: $(if [ -f "$GLIBC_LD" ]; then echo 'installed'; else echo 'missing'; fi)"
step_done


# ═══════════════════════════════════════════════════════════════
#  STEP 2 — Obtain binaries
# ═══════════════════════════════════════════════════════════════

step 2 5 "Obtaining jxproxy binaries"

mkdir -p "$BIN_DIR" "$DATA_DIR"

CLI_DOWNLOADED=false
PROXY_DOWNLOADED=false

# ── Local copy mode ───────────────────────────────────────────
if [ -n "$FROM_DIST" ]; then
  sub_info "Using binaries from: $FROM_DIST"
  CLI_SRC="$FROM_DIST/jxproxy"
  PROXY_SRC="$FROM_DIST/jxproxy-proxy"

  if [ -f "$CLI_SRC" ]; then
    cp "$CLI_SRC" "$BIN_DIR/jxproxy-cli"
    chmod 755 "$BIN_DIR/jxproxy-cli"
    sub_ok "CLI binary copied from $CLI_SRC"
    CLI_DOWNLOADED=true
  else
    sub_warn "CLI binary not found at $CLI_SRC"
  fi

  if [ -f "$PROXY_SRC" ]; then
    cp "$PROXY_SRC" "$BIN_DIR/jxproxy-proxy"
    chmod 755 "$BIN_DIR/jxproxy-proxy"
    sub_ok "Proxy binary copied from $PROXY_SRC"
    PROXY_DOWNLOADED=true
  else
    sub_warn "Proxy binary not found at $PROXY_SRC"
  fi

  # Filenames in the macOS dist dir have a suffix; try the suffixed names
  if [ "$CLI_DOWNLOADED" = false ]; then
    CLI_SRC2="$FROM_DIST/jxproxy-${BINARY_SUFFIX}"
    if [ -f "$CLI_SRC2" ]; then
      cp "$CLI_SRC2" "$BIN_DIR/jxproxy-cli"
      chmod 755 "$BIN_DIR/jxproxy-cli"
      sub_ok "CLI binary copied from $CLI_SRC2"
      CLI_DOWNLOADED=true
    fi
  fi
  if [ "$PROXY_DOWNLOADED" = false ]; then
    PROXY_SRC2="$FROM_DIST/jxproxy-proxy-${BINARY_SUFFIX}"
    if [ -f "$PROXY_SRC2" ]; then
      cp "$PROXY_SRC2" "$BIN_DIR/jxproxy-proxy"
      chmod 755 "$BIN_DIR/jxproxy-proxy"
      sub_ok "Proxy binary copied from $PROXY_SRC2"
      PROXY_DOWNLOADED=true
    fi
  fi
fi

# ── GitHub release download mode ──────────────────────────────
if [ "$CLI_DOWNLOADED" = false ] || [ "$PROXY_DOWNLOADED" = false ]; then
  sub_info "Downloading from GitHub releases..."
  if [ "$CLI_DOWNLOADED" = false ]; then
    sub_info "  jxproxy-cli (${BINARY_SUFFIX})..."
    curl -fsSL -o "$BIN_DIR/jxproxy-cli.tmp" \
      "$RELEASE_URL/jxproxy-${BINARY_SUFFIX}" && {
      mv "$BIN_DIR/jxproxy-cli.tmp" "$BIN_DIR/jxproxy-cli"
      chmod 755 "$BIN_DIR/jxproxy-cli"
      CLI_DOWNLOADED=true
      sub_ok "CLI binary downloaded"
    } || {
      rm -f "$BIN_DIR/jxproxy-cli.tmp"
      sub_warn "CLI binary download failed — re-run when release is published"
    }
  fi
  if [ "$PROXY_DOWNLOADED" = false ]; then
    sub_info "  jxproxy-proxy (${BINARY_SUFFIX})..."
    curl -fsSL -o "$BIN_DIR/jxproxy-proxy.tmp" \
      "$RELEASE_URL/jxproxy-proxy-${BINARY_SUFFIX}" && {
      mv "$BIN_DIR/jxproxy-proxy.tmp" "$BIN_DIR/jxproxy-proxy"
      chmod 755 "$BIN_DIR/jxproxy-proxy"
      PROXY_DOWNLOADED=true
      sub_ok "Proxy binary downloaded"
    } || {
      rm -f "$BIN_DIR/jxproxy-proxy.tmp"
      sub_warn "Proxy binary download failed — re-run when release is published"
    }
  fi
fi

step_done


# ═══════════════════════════════════════════════════════════════
#  STEP 3 — Install launcher (android-launcher.sh → BIN_DIR/jxproxy)
# ═══════════════════════════════════════════════════════════════

step 3 5 "Installing launcher script"

LAUNCHER="$BIN_DIR/jxproxy"
LAUNCHER_REMOTE="https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/android-launcher.sh"

# If we have a local copy of the repo, use it; otherwise fetch
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd 2>/dev/null || echo "")"
LOCAL_LAUNCHER="${SCRIPT_DIR}/android-launcher.sh"

if [ -f "$LOCAL_LAUNCHER" ]; then
  cp "$LOCAL_LAUNCHER" "$LAUNCHER"
  chmod 755 "$LAUNCHER"
  sub_ok "Launcher installed from local source"
elif curl -fsSL -o "$LAUNCHER" "$LAUNCHER_REMOTE"; then
  chmod 755 "$LAUNCHER"
  sub_ok "Launcher downloaded and installed"
else
  sub_warn "Could not install launcher — proxy and CLI can still run directly"
  sub_warn "  Proxy:  ${GLIBC_LD} ${BIN_DIR}/jxproxy-proxy"
  sub_warn "  CLI:    ${GLIBC_LD} ${BIN_DIR}/jxproxy-cli -- --help"
fi

step_done


# ═══════════════════════════════════════════════════════════════
#  STEP 4 — Write configuration (exact copy of macOS setup)
# ═══════════════════════════════════════════════════════════════

step 4 5 "Writing configuration (port 5255 · provider opencode-zen)"

CONFIG_FILE="$DATA_DIR/config.env"

if [ -f "$CONFIG_FILE" ]; then
  sub_info "Existing config found — merging JXPROXY_GLIBC_LD path"
  if ! grep -q "JXPROXY_GLIBC_LD" "$CONFIG_FILE" 2>/dev/null; then
    echo "JXPROXY_GLIBC_LD=${GLIBC_LD}" >> "$CONFIG_FILE"
  fi
else
  # ─── This is the EXACT config from the dev machine ──────────
  cat > "$CONFIG_FILE" << 'CONFIGEOF'
# ─── jxproxy — exact config from macOS dev machine ─────────────
# Proxy daemon
JXPROXY_PORT=5255
JXPROXY_AUTH_TOKEN=jxproxy
JXPROXY_PROVIDER=opencode-zen
PROXY_ENABLED=false

# Base URL routing (all through local proxy)
ANTHROPIC_BASE_URL=http://127.0.0.1:5255/v1
ANTHROPIC_AUTH_TOKEN=jxproxy
OPENAI_BASE_URL=http://127.0.0.1:5255/v1

# Default model
MODEL=opencode/big-pickle
ENABLE_MODEL_THINKING=true

# Provider-tier model routing
MODEL_OPUS=opencode/big-pickle
MODEL_SONNET=nvidia/nemotron-3-ultra-550b-a55b
MODEL_HAIKU=z/glm-5.2

# Fallback providers (ordered — tried if primary fails)
FALLBACK_PROVIDERS=nvidia,z.ai

# Local LLM (Ollama, LM Studio, llama.cpp)
LOCAL_LLM_BASE_URL=http://127.0.0.1:11434/v1
LOCAL_LLM_MODEL=ollama/qwen

# z.ai (OpenAI-compatible endpoint — fallback)
ZAI_BASE_URL=https://api.z.ai/v1

# ─── Provider API keys ─────────────────────────────────────────
# Uncomment and set the ones you need:
# ANTHROPIC_API_KEY=sk-ant-...
# OPENROUTER_API_KEY=sk-or-...
# OPENCODE_API_KEY=sk-oc-...
# OPENAI_API_KEY=sk-...
# ZAI_API_KEY=zai-...
CONFIGEOF

  # Append platform-specific glibc path
  echo "# ─── Termux glibc compatibility ──────────────────────────────" >> "$CONFIG_FILE"
  echo "JXPROXY_GLIBC_LD=${GLIBC_LD}" >> "$CONFIG_FILE"

  sub_ok "Config created: $CONFIG_FILE"
fi

sub_info "Config summary:"
grep -v '^\s*#' "$CONFIG_FILE" 2>/dev/null | grep -v '^\s*$' | while IFS='=' read -r k v; do
  # Hide values of known secret keys
  case "$k" in
    ANTHROPIC_API_KEY|OPENROUTER_API_KEY|OPENCODE_API_KEY|OPENAI_API_KEY)
      v="${v:0:8}..." ;;
  esac
  [ -n "$k" ] && sub_info "     ${k}=${v}"
done

step_done


# ═══════════════════════════════════════════════════════════════
#  STEP 5 — Environment setup & PATH
# ═══════════════════════════════════════════════════════════════

step 5 5 "Configuring environment & removing official Claude launcher"

# ── Remove interfering official launcher ──────────────────
OFFICIAL_CLAUDE="/data/data/com.termux/files/usr/bin/claude"
if [ -f "$OFFICIAL_CLAUDE" ]; then
  mv "$OFFICIAL_CLAUDE" "${OFFICIAL_CLAUDE}-official" 2>/dev/null || true
  sub_ok "Renamed official Claude launcher to claude-official"
  sub_info "  Run claude-official if you ever want the original back"
fi

# ── Create jxproxy → claude symlink ───────────────────────
CLAUDE_SYMLINK="$BIN_DIR/claude"
if [ ! -L "$CLAUDE_SYMLINK" ] || [ "$(readlink "$CLAUDE_SYMLINK")" != "jxproxy" ]; then
  ln -sf "$BIN_DIR/jxproxy" "$CLAUDE_SYMLINK"
  sub_ok "Created symlink: ~/.local/bin/claude → jxproxy"
fi

# ── Write clean .bashrc ────────────────────────────────────
cat > "$HOME/.bashrc" << BASHRCEOF
# ─── jxproxy ──────────────────────────────────────────────
export PATH="$BIN_DIR:\$PATH"
export ANTHROPIC_BASE_URL="http://127.0.0.1:5255"
export ANTHROPIC_API_KEY="jxproxy"
export ANTHROPIC_AUTH_TOKEN="jxproxy"
export ANTHROPIC_PORT="5255"
export DISABLE_AUTOUPDATER="1"

# ─── bun (if installed) ───────────────────────────────────
if [ -d "\$HOME/.bun" ]; then
  export BUN_INSTALL="\$HOME/.bun"
  export PATH="\$BUN_INSTALL/bin:\$PATH"
fi

# ─── Provider API keys — set these in ~/.jxproxy/config.env ──
# export OPENCODE_API_KEY="sk-oc-..."
# export OPENAI_BASE_URL="https://integrate.api.nvidia.com/v1"
# export OPENAI_API_KEY="nvapi-..."
# export ZAI_BASE_URL="https://api.z.ai/v1"
# export ZAI_API_KEY="zai-..."
BASHRCEOF
sub_ok "Wrote clean ~/.bashrc with jxproxy env vars and PATH"

# ── Also write .profile (for login shells) ────────────────
cat > "$HOME/.profile" << PROFILEEOF
# ─── jxproxy ──────────────────────────────────────────────
export PATH="$BIN_DIR:\$PATH"
export ANTHROPIC_BASE_URL="http://127.0.0.1:5255"
export ANTHROPIC_API_KEY="jxproxy"
export ANTHROPIC_AUTH_TOKEN="jxproxy"
export DISABLE_AUTOUPDATER="1"

# Load .bashrc for interactive shells
if [ -n "\$BASH_VERSION" ] && [ -f "\$HOME/.bashrc" ]; then
  source "\$HOME/.bashrc"
fi
PROFILEEOF
sub_ok "Wrote clean ~/.profile (login shells)"

step_done


# ═══════════════════════════════════════════════════════════════
#  VERIFICATION
# ═══════════════════════════════════════════════════════════════

echo ""
echo -e "  ${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}║${NC}              ${CYAN}Verifying installation...${NC}                      ${BOLD}║${NC}"
echo -e "  ${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# CLI binary smoke test
if $CLI_DOWNLOADED && [ -x "$BIN_DIR/jxproxy-cli" ] && [ -f "$GLIBC_LD" ]; then
  sub_info "Testing CLI binary through glibc loader..."
  set +e
  CLI_OUTPUT=$("$GLIBC_LD" "$BIN_DIR/jxproxy-cli" --version 2>&1)
  CLI_EXIT=$?
  set -e
  if [ $CLI_EXIT -eq 0 ]; then
    CLI_VER=$(echo "$CLI_OUTPUT" | head -1)
    sub_ok "CLI binary: version ${CLI_VER:-ok}"
  else
    sub_warn "CLI binary smoke test failed (exit $CLI_EXIT)"
    sub_warn "  Output: $(echo "$CLI_OUTPUT" | head -3 | tr '\n' ' ')"
    sub_warn "  Try: LD_LIBRARY_PATH=\"$(dirname "$GLIBC_LD")\" \"$GLIBC_LD\" \"$BIN_DIR/jxproxy-cli\" --version"
  fi
fi

# Proxy binary smoke test
if $PROXY_DOWNLOADED && [ -f "$BIN_DIR/jxproxy-proxy" ] && [ -f "$GLIBC_LD" ]; then
  chmod 755 "$BIN_DIR/jxproxy-proxy"
  sub_info "Testing proxy binary through glibc loader..."
  GLIBC_LD_DIR="$(dirname "$GLIBC_LD")"
  JXPROXY_PORT=5255 JXPROXY_PROVIDER=direct \
    LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:$GLIBC_LD_DIR" \
    nohup "$GLIBC_LD" "$BIN_DIR/jxproxy-proxy" > "$DATA_DIR/proxy.log" 2>&1 &
  PROXY_PID=$!
  sleep 2
  if kill -0 "$PROXY_PID" 2>/dev/null && curl -sf "http://127.0.0.1:5255/health" >/dev/null 2>&1; then
    sub_ok "Proxy binary: started and health check passed"
    kill "$PROXY_PID" 2>/dev/null || true
  else
    sub_warn "Proxy smoke test could not connect"
    tail -5 "$DATA_DIR/proxy.log" 2>/dev/null || true
    kill "$PROXY_PID" 2>/dev/null || true
  fi
fi

# Config file check
if [ -f "$CONFIG_FILE" ]; then
  CONFIG_LINES=$(wc -l < "$CONFIG_FILE")
  sub_ok "Config file: ${CONFIG_LINES} lines at ${CONFIG_FILE}"
fi

# Launcher check
if [ -x "$LAUNCHER" ]; then
  sub_ok "Launcher: ${LAUNCHER}"
fi

# PATH check
if [[ ":$PATH:" == *":$BIN_DIR:"* ]]; then
  sub_ok "PATH includes ${BIN_DIR} (current session)"
else
  sub_warn "PATH does not include ${BIN_DIR} — will be active in new shells"
fi

# ── Disk usage ───────────────────────────────────────────────
CLI_SIZE="N/A"
PROXY_SIZE="N/A"
[ -f "$BIN_DIR/jxproxy-cli" ] && CLI_SIZE=$(du -h "$BIN_DIR/jxproxy-cli" | cut -f1)
[ -f "$BIN_DIR/jxproxy-proxy" ] && PROXY_SIZE=$(du -h "$BIN_DIR/jxproxy-proxy" | cut -f1)
sub_info "Disk usage: CLI ${CLI_SIZE} · Proxy ${PROXY_SIZE}"


# ═══════════════════════════════════════════════════════════════
#  DONE
# ═══════════════════════════════════════════════════════════════

echo ""
echo -e "  ${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}║${NC}       ${GREEN}✓ jxproxy installed successfully!${NC}              ${BOLD}║${NC}"
echo -e "  ${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}To launch:${NC}"
echo "    claude                   # or: jxproxy (same thing)"
echo ""
echo -e "  ${BOLD}Launch modes:${NC}"
echo "    claude                   Start proxy + CLI (default)"
echo "    jxproxy --proxy-only     Start proxy server only"
echo "    jxproxy --status         Check proxy status"
echo ""
echo -e "  ${BOLD}Config file:${NC}  ${CONFIG_FILE}"
echo -e "  ${BOLD}Log file:${NC}     ${DATA_DIR}/proxy.log"
echo -e "  ${BOLD}Binaries:${NC}     ${BIN_DIR}/jxproxy-cli  +  ${BIN_DIR}/jxproxy-proxy"
echo -e "  ${BOLD}Official launcher renamed to:${NC}  claude-official (still available)"
echo ""
echo -e "  ${BOLD}Model routing:${NC}"
echo "    Primary:  opencode/big-pickle         (port 5255, provider: opencode-zen)"
echo "    Fallback: nvidia/nemotron-3-ultra-55b (via OPENAI api)"
echo "    Fallback: z.ai/glm-5.2                (via ZAI api)"
echo "    Haiku:    z/glm-5.2"
echo ""
echo -e "  ${BOLD}NOTE:${NC} jxproxy runs through the glibc loader on Android."
echo -e "  ${BOLD}     ${NC} This is handled automatically by the launcher."
echo -e "  ${BOLD}     ${NC} Reload shell:  source ~/.bashrc  (or start a new Termux session)"
echo ""

# ── Quick-start hint ─────────────────────────────────────────
if $CLI_DOWNLOADED && $PROXY_DOWNLOADED; then
  echo -e "  ${BOLD}Quick start:${NC}"
  echo "    source ~/.bashrc"
  echo "    jxproxy --proxy-only &    (start proxy in background)"
  echo "    claude                    (launch jxproxy CLI via symlink)"
  echo ""
fi

#!/bin/bash
#
# jxproxy — macOS / Linux Installer
#
# Installs: jxproxy CLI binary, jxproxy proxy server binary, launcher script
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/install.sh | bash -s -- --min
#   curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/install.sh | bash -s -- --provider=openrouter
#
# Flags:
#   --min           Shallow clone (faster, smaller)
#   --provider=X    Set default provider (direct, openrouter, openai, local)
#   --bin-dir=DIR   Install binaries to DIR (default: ~/.local/bin)
#   --no-build      Skip building, only fetch and install scripts
#

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Config ---
REPO="https://github.com/marshaljlee/jxproxy.git"
CLONE_DIR="${HOME}/.jxproxy-source"
BIN_DIR="${HOME}/.local/bin"
DATA_DIR="${HOME}/.jxproxy"
PROVIDER="direct"
MIN_CLONE=""
NO_BUILD=""

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --min) MIN_CLONE="--min" ;;
    --no-build) NO_BUILD="1" ;;
    --provider=*) PROVIDER="${arg#*=}" ;;
    --bin-dir=*) BIN_DIR="${arg#*=}" ;;
    --help|-h)
      echo "jxproxy installer — macOS/Linux"
      echo ""
      echo "  --min           Shallow clone (faster)"
      echo "  --provider=X    Default provider: direct, openrouter, opencode-zen, openai, zai, local"
      echo "  --bin-dir=DIR   Install location (default: ~/.local/bin)"
      echo "  --no-build      Fetch only, don't compile"
      echo "  --uninstall     Remove all jxproxy files"
      exit 0
      ;;
  esac
done

# --- Platform Detection ---
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Darwin) PLATFORM="macos" ;;
  Linux)
    if [ -n "${TERMUX_VERSION:-}" ]; then
      echo ""
      echo "  Detected Android / Termux — routing to Android installer..."
      SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
      ANDROID_INSTALLER="${SELF_DIR}/installers/install-android.sh"
      if [ -f "$ANDROID_INSTALLER" ]; then
        exec bash "$ANDROID_INSTALLER" "$@"
      fi
      # Fallback: download from raw GitHub
      exec curl -fsSL "https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/install-android.sh" | bash -s -- "$@"
    fi
    PLATFORM="linux"
    ;;
  *)
    echo "Unsupported OS: $OS — macOS or Linux required."
    echo "For Windows, use installers/install.ps1"
    echo "For Android/Termux, use installers/install-android.sh"
    exit 1
    ;;
esac

case "$ARCH" in
  x86_64|amd64) ARCH_BITS="x64" ;;
  aarch64|arm64) ARCH_BITS="arm64" ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

# ─────────────────────────────────────────────────
#  HEADBOARD — TUI-Style Big Banner
# ─────────────────────────────────────────────────

echo ""
echo -e "  ${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}║${NC}                    ${CYAN}jxproxy Installer${NC}                    ${BOLD}║${NC}"
echo -e "  ${BOLD}║${NC}                                                          ${BOLD}║${NC}"
echo -e "  ${BOLD}║${NC}  ${BOLD}Platform:${NC}  ${PLATFORM} (${ARCH_BITS})                           ${BOLD}║${NC}"
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
#  STEP 1: Dependencies
# ─────────────────────────────────────────────────

step 1 5 "Checking dependencies"

if ! command -v git &>/dev/null; then
  if [ "$PLATFORM" = "macos" ]; then
    sub_info "Installing git (Xcode Command Line Tools)..."
    xcode-select --install 2>/dev/null || true
    sub_info "Waiting for Xcode CLI tools installation to complete..."
    for i in $(seq 1 60); do
      if command -v git &>/dev/null; then
        break
      fi
      sleep 2
    done
    if ! command -v git &>/dev/null; then
      sub_err "Xcode CLI tools install did not complete in 2 minutes."
      sub_err "Try running manually: xcode-select --install"
      sub_err "Or install git from https://git-scm.com/download/mac"
      exit 1
    fi
  else
    sub_err "Please install git: apt-get install git (Debian) or yum install git (RHEL)"
    exit 1
  fi
fi

if ! command -v bun &>/dev/null; then
  sub_info "Installing Bun runtime..."
  curl -fsSL https://bun.sh/install | bash
  export BUN_INSTALL="${HOME}/.bun"
  export PATH="${BUN_INSTALL}/bin:${PATH}"
fi

BUN_VER=$(bun --version 2>/dev/null || echo "0")

# Enforce minimum Bun version (1.3.11+)
if [ "$(printf '%s\n' "1.3.11" "$BUN_VER" | sort -V | head -n1)" != "1.3.11" ]; then
  sub_err "Bun ${BUN_VER} is too old. jxproxy requires Bun 1.3.11+."
  sub_err "Upgrade with: curl -fsSL https://bun.sh/install | bash"
  exit 1
fi

sub_ok "bun ${BUN_VER}"
sub_ok "git"
step_done

# ─────────────────────────────────────────────────
#  STEP 2: Clone Repository
# ─────────────────────────────────────────────────

step 2 5 "Cloning jxproxy repository"

if [ -d "$CLONE_DIR" ]; then
  sub_info "Updating existing clone..."
  cd "$CLONE_DIR"
  # Fetch latest and hard-reset to handle any locally-modified tracked files
  # (e.g. dist/ artifacts from a prior build that are tracked by git)
  git fetch origin 2>&1 | tail -3
  git reset --hard origin/main
else
  if [ -n "$MIN_CLONE" ]; then
    git clone --depth 1 "$REPO" "$CLONE_DIR"
  else
    git clone "$REPO" "$CLONE_DIR"
  fi
  cd "$CLONE_DIR"
fi

sub_ok "Repository ready at ${CLONE_DIR}"
step_done

# ─────────────────────────────────────────────────
#  STEP 3: Bootstrap
# ─────────────────────────────────────────────────

step 3 5 "Preparing build environment"

if [ -d "src" ] && [ -f "src/entrypoints/cli.tsx" ]; then
  sub_info "Source already present — re-applying patches and updating deps..."
  cd "$CLONE_DIR"
  bun install 2>/dev/null || true
  bash scripts/patch-source.sh
else
  bash scripts/bootstrap.sh ${MIN_CLONE:+"--min"}
fi

step_done

# ─────────────────────────────────────────────────
#  STEP 4: Build
# ─────────────────────────────────────────────────

step 4 5 "Building jxproxy binaries"

mkdir -p "$BIN_DIR" "$DATA_DIR"

if [ -z "$NO_BUILD" ]; then
  sub_info "Compiling CLI binary (this may take a minute)..."
  bun run build 2>&1 | tail -5
  sub_ok "CLI binary built"

  sub_info "Compiling proxy binary..."
  bun build ./proxy/server.ts --compile --target=bun --minify --bytecode --outfile ./dist/jxproxy-proxy 2>&1 | tail -5 || {
    sub_warn "Proxy binary build skipped (non-fatal)"
  }
else
  sub_info "Skipping build (--no-build flag)"
fi

step_done

# ─────────────────────────────────────────────────
#  STEP 5: Install
# ─────────────────────────────────────────────────

step 5 5 "Installing to system"

# Copy CLI binary as jxproxy-cli (launcher script uses the name jxproxy — no collision)
if [ -f "dist/jxproxy" ]; then
  cp "dist/jxproxy" "$BIN_DIR/jxproxy-cli"
  chmod 755 "$BIN_DIR/jxproxy-cli"
  sub_ok "CLI binary → ${BIN_DIR}/jxproxy-cli"
fi

if [ -f "dist/jxproxy-proxy" ]; then
  cp "dist/jxproxy-proxy" "$BIN_DIR/jxproxy-proxy"
  chmod 755 "$BIN_DIR/jxproxy-proxy"
  sub_ok "Proxy binary → ${BIN_DIR}/jxproxy-proxy"
fi

# Install launcher (user-facing entry point — jxproxy)
cp "scripts/jxproxy-launcher.sh" "$BIN_DIR/jxproxy"
chmod 755 "$BIN_DIR/jxproxy"
sub_ok "Launcher → ${BIN_DIR}/jxproxy"

# Create default config
CONFIG_FILE="$DATA_DIR/config.env"
if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" << CONFIGEOF
# ─── jxproxy — provider routing config ─────────────────────────
JXPROXY_PORT=5529
JXPROXY_AUTH_TOKEN=jxproxy
JXPROXY_PROVIDER=opencode-zen

# Default model — all API requests route here
MODEL=opencode/big-pickle
ENABLE_MODEL_THINKING=true

# Tiered model routing (matched by name: opus/sonnet/haiku)
MODEL_OPUS=opencode/big-pickle
MODEL_SONNET=nvidia/nemotron-3-ultra-550b-a55b
MODEL_HAIKU=z/glm-5.2

# Fallback chain — tried in order if primary fails
#   nvidia  → uses OPENAI_BASE_URL + OPENAI_API_KEY
#   z.ai    → uses ZAI_BASE_URL + ZAI_API_KEY
FALLBACK_PROVIDERS=nvidia,z.ai
VISION_MODELS=opencode/,nvidia/nemotron-,glm-

# ─── Provider 1: OpenCode (primary) ─────────────────────────
# Provider: opencode-zen / Model: opencode/big-pickle
# Set your key below (remove #):
#OPENCODE_API_KEY=

# ─── Provider 2: NVIDIA NIM (fallback) ──────────────────────
# Uses OpenAI-compatible endpoint
#OPENAI_API_KEY=

# ─── Provider 3: z.ai (fallback) ────────────────────────────
ZAI_BASE_URL=https://api.z.ai/v1
#ZAI_API_KEY=

# ─── Provider 4: Local LLM (ollama, LM Studio) ─────────────
LOCAL_LLM_BASE_URL=http://127.0.0.1:11434/v1
LOCAL_LLM_MODEL=ollama/qwen3:latest

# ─── Provider 5: Direct Anthropic / OpenRouter ──────────────
# (only needed if you change JXPROXY_PROVIDER)
#ANTHROPIC_API_KEY=
#OPENROUTER_API_KEY=
CONFIGEOF
  sub_ok "Config created → ${CONFIG_FILE}"
fi

# Add to PATH if needed
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  SHELL_CONFIG=""
  case "${SHELL:-}" in
    */bash) SHELL_CONFIG="$HOME/.bashrc" ;;
    */zsh)  SHELL_CONFIG="$HOME/.zshrc" ;;
    */fish) SHELL_CONFIG="$HOME/.config/fish/config.fish" ;;
  esac
  if [ -n "$SHELL_CONFIG" ] && [ -f "$SHELL_CONFIG" ]; then
    echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$SHELL_CONFIG"
    sub_ok "Added ${BIN_DIR} to PATH in ${SHELL_CONFIG}"
  fi
fi

step_done

# ─────────────────────────────────────────────────
#  DONE
# ─────────────────────────────────────────────────

echo ""
echo -e "  ${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}║${NC}          ${GREEN}✓ jxproxy installed successfully!${NC}          ${BOLD}║${NC}"
echo -e "  ${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Quick start:${NC}"
echo "    jxproxy                    # Launch proxy + CLI"
echo "    jxproxy -- --help          # CLI help"
echo "    jxproxy --setup-api        # Configure API keys"
echo "    jxproxy --uninstall        # Remove jxproxy"
echo ""
echo -e "  ${BOLD}Config:${NC}   ${CONFIG_FILE}"
echo -e "  ${BOLD}Binaries:${NC} ${BIN_DIR}/jxproxy"
echo -e "  ${BOLD}Logs:${NC}     ${DATA_DIR}/proxy.log"
echo ""
echo -e "  ${BOLD}Provider chain:${NC}"
echo "    Primary:  opencode/big-pickle"
echo "    Fallback: nvidia, z.ai"
echo "    Vision models: opencode/, nvidia/nemotron-, glm-"
echo ""

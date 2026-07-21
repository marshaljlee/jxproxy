#!/data/data/com.termux/files/usr/bin/bash
#
# jxproxy — One-Shot Termux Installer
#
# Installs everything from scratch: dependencies, bun, glibc, repo,
# config, launcher, permissions. One command, done.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/install-once.sh | bash
#
#   # With API key upfront (non-interactive):
#   curl -fsSL ... | bash -s -- --api-key=sk-xxx...
#
#   # Uninstall:
#   curl -fsSL ... | bash -s -- --uninstall
#
# What it installs:
#   1. System deps: curl, git, bun, glibc-runner
#   2. Clones marshaljlee/jxproxy to ~/.jxproxy-source
#   3. Launcher at ~/.local/bin/jxproxy (+ claude symlink)
#   4. Config at ~/.jxproxy/config.env
#   5. PATH + env vars in ~/.bashrc and ~/.profile
#   6. Verifies everything works
#

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
#  CONFIG
# ═══════════════════════════════════════════════════════════════

GH_REPO="marshaljlee/jxproxy"
REPO_URL="https://github.com/$GH_REPO.git"
BIN_DIR="${HOME}/.local/bin"
DATA_DIR="${HOME}/.jxproxy"
SOURCE_DIR="${HOME}/.jxproxy-source"
CONFIG_FILE="$DATA_DIR/config.env"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
GLIBC_PREFIX="${PREFIX}/glibc"

ARCH=$(uname -m)
case "$ARCH" in
  aarch64) GLIBC_LD_NAME="ld-linux-aarch64.so.1" ;;
  x86_64)  GLIBC_LD_NAME="ld-linux-x86-64.so.2" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac
GLIBC_LD="${GLIBC_PREFIX}/lib/${GLIBC_LD_NAME}"

API_KEY=""
UNINSTALL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --api-key=*)  API_KEY="${1#*=}"; shift ;;
    --api-key)    API_KEY="$2"; shift 2 ;;
    --uninstall)  UNINSTALL="1"; shift ;;
    --help|-h)
      echo "Usage: bash install-once.sh [--api-key=KEY] [--uninstall]"
      exit 0
      ;;
    *) shift ;;
  esac
done

# ═══════════════════════════════════════════════════════════════
#  UNINSTALL
# ═══════════════════════════════════════════════════════════════

if [ -n "$UNINSTALL" ]; then
  echo "Removing jxproxy..."
  rm -f "$BIN_DIR/jxproxy" "$BIN_DIR/jxproxy-cli" "$BIN_DIR/jxproxy-proxy" "$BIN_DIR/claude"
  rm -rf "$DATA_DIR" "$SOURCE_DIR"
  for rc in "$HOME/.bashrc" "$HOME/.profile"; do
    [ -f "$rc" ] && sed -i '/# >>> jxproxy/,/# <<< jxproxy/d' "$rc" 2>/dev/null || true
    [ -f "$rc" ] && sed -i '/jxproxy/d' "$rc" 2>/dev/null || true
  done
  echo "Done. Removed: binaries, config, source, shell entries."
  exit 0
fi

# ═══════════════════════════════════════════════════════════════
#  COLORS
# ═══════════════════════════════════════════════════════════════

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
err()   { echo -e "  ${RED}✗${NC} $1" >&2; }
step()  { echo -e "\n${BOLD}[$1]${NC} $2"; }

# ═══════════════════════════════════════════════════════════════
#  TERMUX GUARD
# ═══════════════════════════════════════════════════════════════

if [ -z "${TERMUX_VERSION:-}" ]; then
  err "This installer is for Termux on Android."
  err "Install from F-Droid: https://f-droid.org/packages/com.termux/"
  exit 1
fi

echo ""
echo -e "  ${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}║${NC}      ${CYAN}jxproxy — One-Shot Installer${NC}                      ${BOLD}║${NC}"
echo -e "  ${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"

# ═══════════════════════════════════════════════════════════════
#  STEP 1 — System packages
# ═══════════════════════════════════════════════════════════════

step "1/6" "Installing system packages"

pkg update -y 2>/dev/null || true
pkg install -y curl git 2>/dev/null || true

# glibc-runner — required for bun-compiled binaries on Android
if [ ! -f "$GLIBC_LD" ]; then
  pkg install -y glibc-repo 2>/dev/null || true
  pkg update 2>/dev/null || true
  pkg install -y glibc-runner 2>/dev/null || {
    err "Failed to install glibc-runner."
    err "See: https://github.com/termux/termux-packages/wiki/glibc"
    exit 1
  }
fi
ok "glibc-runner: $GLIBC_LD"

# ═══════════════════════════════════════════════════════════════
#  STEP 2 — Bun runtime
# ═══════════════════════════════════════════════════════════════

step "2/6" "Installing bun runtime"

BUN_BIN="${HOME}/.bun/bin/bun"
if [ -x "$BUN_BIN" ]; then
  ok "bun already installed"
else
  curl -fsSL https://bun.sh/install | bash 2>/dev/null || {
    err "Failed to install bun"
    exit 1
  }
  ok "bun installed at $BUN_BIN"
fi

# Verify bun runs through glibc loader
if [ -f "$GLIBC_LD" ]; then
  BUN_VER=$("$GLIBC_LD" "$BUN_BIN" --version 2>/dev/null || echo "fail")
  if [ "$BUN_VER" = "fail" ]; then
    warn "bun --version failed through glibc loader (may still work)"
  else
    ok "bun $BUN_VER (via glibc)"
  fi
fi

# ═══════════════════════════════════════════════════════════════
#  STEP 3 — Clone / update source repo
# ═══════════════════════════════════════════════════════════════

step "3/6" "Cloning jxproxy source"

mkdir -p "$BIN_DIR" "$DATA_DIR"

if [ -d "$SOURCE_DIR/.git" ]; then
  ok "Source repo exists — pulling latest"
  git -C "$SOURCE_DIR" pull --ff-only 2>/dev/null || warn "Pull failed (using existing)"
else
  rm -rf "$SOURCE_DIR"
  git clone "$REPO_URL" "$SOURCE_DIR" 2>/dev/null || {
    err "Failed to clone $REPO_URL"
    exit 1
  }
  ok "Cloned to $SOURCE_DIR"
fi

# ═══════════════════════════════════════════════════════════════
#  STEP 4 — Install launcher
# ═══════════════════════════════════════════════════════════════

step "4/6" "Installing launcher"

LAUNCHER_SRC="$SOURCE_DIR/installers/android-launcher.sh"
LAUNCHER_DST="$BIN_DIR/jxproxy"

if [ -f "$LAUNCHER_SRC" ]; then
  cp "$LAUNCHER_SRC" "$LAUNCHER_DST"
  chmod 755 "$LAUNCHER_DST"
  ok "Launcher: $LAUNCHER_DST"
else
  err "Launcher source not found: $LAUNCHER_SRC"
  exit 1
fi

# Symlink: claude → jxproxy
ln -sf "$BIN_DIR/jxproxy" "$BIN_DIR/claude"
ok "Symlink: claude → jxproxy"

# ═══════════════════════════════════════════════════════════════
#  STEP 5 — Config
# ═══════════════════════════════════════════════════════════════

step "5/6" "Writing config"

if [ -f "$CONFIG_FILE" ]; then
  ok "Config exists — keeping (edit ~/.jxproxy/config.env to change)"
else
  cat > "$CONFIG_FILE" << 'CFGEOF'
# jxproxy — provider routing config
JXPROXY_PORT=5255
JXPROXY_AUTH_TOKEN=jxproxy
JXPROXY_PROVIDER=opencode-zen

# Proxy routing
ANTHROPIC_BASE_URL=http://127.0.0.1:5255/v1
ANTHROPIC_AUTH_TOKEN=jxproxy
OPENAI_BASE_URL=http://127.0.0.1:5255/v1

# Default model
MODEL=opencode/big-pickle
ENABLE_MODEL_THINKING=true

# Tiered model routing
MODEL_OPUS=opencode/big-pickle
MODEL_SONNET=nvidia/nemotron-3-ultra-550b-a55b
MODEL_HAIKU=z/glm-5.2

# Fallback providers (tried in order)
FALLBACK_PROVIDERS=nvidia,z.ai

# API keys — set below or run 'jxproxy --setup-api' later
#OPENCODE_API_KEY=
#OPENAI_API_KEY=
ZAI_BASE_URL=https://api.z.ai/v1
#ZAI_API_KEY=

# Termux glibc path
CFGEOF
  echo "JXPROXY_GLIBC_LD=${GLIBC_LD}" >> "$CONFIG_FILE"
  ok "Config: $CONFIG_FILE"
fi

# Inject API key if provided
if [ -n "$API_KEY" ]; then
  if grep -q "^#OPENCODE_API_KEY=" "$CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^#OPENCODE_API_KEY=.*|OPENCODE_API_KEY=${API_KEY}|" "$CONFIG_FILE"
    ok "API key saved to config"
  elif grep -q "^OPENCODE_API_KEY=" "$CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^OPENCODE_API_KEY=.*|OPENCODE_API_KEY=${API_KEY}|" "$CONFIG_FILE"
    ok "API key updated in config"
  else
    echo "OPENCODE_API_KEY=${API_KEY}" >> "$CONFIG_FILE"
    ok "API key appended to config"
  fi
fi

# ═══════════════════════════════════════════════════════════════
#  STEP 6 — Shell environment
# ═══════════════════════════════════════════════════════════════

step "6/6" "Setting up shell environment"

# Remove any existing jxproxy blocks from shell configs
for rc in "$HOME/.bashrc" "$HOME/.profile"; do
  [ -f "$rc" ] && sed -i '/# >>> jxproxy/,/# <<< jxproxy/d' "$rc" 2>/dev/null || true
done

# Write .bashrc block
cat >> "$HOME/.bashrc" << BASHBLOCK

# >>> jxproxy
export PATH="${BIN_DIR}:\$PATH"
export ANTHROPIC_BASE_URL="http://127.0.0.1:5255"
export ANTHROPIC_API_KEY="jxproxy"
export ANTHROPIC_AUTH_TOKEN="jxproxy"
export DISABLE_AUTOUPDATER="1"
# bun
if [ -d "\$HOME/.bun" ]; then
  export BUN_INSTALL="\$HOME/.bun"
  export PATH="\$BUN_INSTALL/bin:\$PATH"
fi
# <<< jxproxy
BASHBLOCK

# Write .profile block
cat >> "$HOME/.profile" << PROFILEBLOCK

# >>> jxproxy
export PATH="${BIN_DIR}:\$PATH"
export ANTHROPIC_BASE_URL="http://127.0.0.1:5255"
export ANTHROPIC_API_KEY="jxproxy"
export ANTHROPIC_AUTH_TOKEN="jxproxy"
export DISABLE_AUTOUPDATER="1"
# <<< jxproxy
PROFILEBLOCK

ok "Shell config written (.bashrc + .profile)"

# ═══════════════════════════════════════════════════════════════
#  VERIFY
# ═══════════════════════════════════════════════════════════════

echo ""
echo -e "  ${BOLD}Verifying...${NC}"

# Test bun can parse the proxy source
if [ -f "$SOURCE_DIR/proxy/server.ts" ]; then
  set +e
  BUN_CHECK=$("$GLIBC_LD" "$BUN_BIN" build "$SOURCE_DIR/proxy/server.ts" --no-bundle 2>&1 | tail -1)
  set -e
  if [ -z "$BUN_CHECK" ] || echo "$BUN_CHECK" | grep -qi "error"; then
    warn "Proxy source syntax check: $BUN_CHECK"
  else
    ok "Proxy source: syntax OK"
  fi
fi

# Test launcher exists and is executable
[ -x "$BIN_DIR/jxproxy" ] && ok "Launcher: executable" || warn "Launcher: not executable"

# Test config exists
[ -f "$CONFIG_FILE" ] && ok "Config: $CONFIG_FILE" || warn "Config: missing"

# Test PATH
export PATH="${BIN_DIR}:$PATH"
command -v jxproxy >/dev/null 2>&1 && ok "jxproxy: on PATH" || warn "jxproxy: not on PATH (new shell needed)"

# ═══════════════════════════════════════════════════════════════
#  DONE
# ═══════════════════════════════════════════════════════════════

echo ""
echo -e "  ${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}║${NC}         ${GREEN}✓ jxproxy installed!${NC}                          ${BOLD}║${NC}"
echo -e "  ${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Quick start:${NC}"
echo "    source ~/.bashrc    # reload environment"
echo "    jxproxy             # start proxy + CLI"
echo ""
echo -e "  ${BOLD}Commands:${NC}"
echo "    jxproxy                Start proxy + Claude Code CLI"
echo "    jxproxy --proxy-only   Start proxy server only"
echo "    jxproxy --status       Check proxy status"
echo "    jxproxy --setup-api    Add / change API keys"
echo "    jxproxy --proxy-stop   Stop the proxy"
echo ""
echo -e "  ${BOLD}Config:${NC}       ~/.jxproxy/config.env"
echo -e "  ${BOLD}Logs:${NC}         ~/.jxproxy/proxy.log"
echo -e "  ${BOLD}Source:${NC}       ~/.jxproxy-source/"
echo ""

if [ -z "$API_KEY" ]; then
  echo -e "  ${YELLOW}Next step:${NC} add your OpenCode API key:"
  echo "    jxproxy --setup-api"
  echo "    # or edit ~/.jxproxy/config.env and uncomment OPENCODE_API_KEY"
  echo ""
fi

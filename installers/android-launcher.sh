#!/data/data/com.termux/files/usr/bin/bash
#
# jxproxy — Android / Termux Launcher
#
# Starts the proxy server and the modified Claude Code CLI on Android/Termux,
# routing all Anthropic API traffic through the proxy.
#
# Bun cross-compiled binaries use glibc, but Android's Bionic linker rejects
# them for PT_TLS alignment on ARM64. All execution goes through the
# glibc-runner loader ("$JXPROXY_GLIBC_LD") explicitly.
#
# Usage:
#   jxproxy                  # Start proxy + CLI
#   jxproxy --proxy-only     # Start proxy server only
#   jxproxy --proxy-reuse    # Use existing proxy, launch CLI only
#   jxproxy --proxy-stop     # Stop the running proxy
#   jxproxy --status         # Check proxy status
#   jxproxy -- --help        # Pass flags through to Claude CLI
#
# Environment:
#   JXPROXY_PORT             — Proxy listen port (default: 5529)
#   JXPROXY_PROVIDER         — Provider backend (default: direct)
#   JXPROXY_DATA_DIR         — Config/data directory (default: ~/.jxproxy)
#   JXPROXY_GLIBC_LD         — glibc loader path (auto-detected from config)
#

set -euo pipefail

# --- Paths ---

BIN_DIR="$(dirname "$0")"
DATA_DIR="${JXPROXY_DATA_DIR:-${HOME}/.jxproxy}"
CONFIG_FILE="$DATA_DIR/config.env"
PID_FILE="$DATA_DIR/proxy.pid"
LOG_FILE="$DATA_DIR/proxy.log"

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

# --- Ensure data directory ---

mkdir -p "$DATA_DIR"

# --- Safe config loading ---

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    while IFS='=' read -r key value; do
      [[ "$key" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${key// /}" ]] && continue
      key="$(echo "$key" | tr -d ' ')"
      value="$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      if [ -n "$key" ]; then
        export "$key=$value"
      fi
    done < "$CONFIG_FILE"
  fi
}

load_config

# --- Defaults ---

JXPROXY_PORT="${JXPROXY_PORT:-5529}"
JXPROXY_AUTH_TOKEN="${JXPROXY_AUTH_TOKEN:-jxproxy}"
JXPROXY_PROVIDER="${JXPROXY_PROVIDER:-direct}"

CLI_BINARY="${JXPROXY_CLI_BINARY:-$BIN_DIR/jxproxy-cli}"
PROXY_BINARY="${JXPROXY_PROXY_BINARY:-$BIN_DIR/jxproxy-proxy}"

# --- glibc loader ---
# On Termux, glibc-runner installs the loader at a known path.
# All jxproxy binaries must run through it (Bionic rejects PT_TLS alignment).
# Can be set via config.env or JXPROXY_GLIBC_LD env var.
if [ -z "${JXPROXY_GLIBC_LD:-}" ]; then
  JXPROXY_GLIBC_LD="/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1"
  if [ ! -x "$JXPROXY_GLIBC_LD" ]; then
    JXPROXY_GLIBC_LD=""
  fi
fi

# --- Help ---

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<EOF
jxproxy — Android/Termux — Claude Code with proxy routing, telemetry stripped

Usage:
  jxproxy                  Start proxy + CLI
  jxproxy --proxy-only     Start proxy server only
  jxproxy --proxy-reuse    Connect to existing proxy, start CLI
  jxproxy --proxy-stop     Stop the running proxy
  jxproxy --status         Check proxy status
  jxproxy -- --help        Pass flags to Claude CLI
  jxproxy --help           Show this help

Config file: $CONFIG_FILE
Data dir:    $DATA_DIR
EOF
  exit 0
fi

# --- Functions ---

run_via_glibc() {
  if [ -n "${JXPROXY_GLIBC_LD:-}" ]; then
    exec env LD_PRELOAD="" "$JXPROXY_GLIBC_LD" "$@"
  else
    exec "$@"
  fi
}

start_proxy() {
  if [ ! -x "$PROXY_BINARY" ]; then
    err "Proxy binary not found: $PROXY_BINARY"
    err "Re-run the installer or place jxproxy-proxy in $BIN_DIR"
    exit 1
  fi

  if [ -f "$PID_FILE" ]; then
    local old_pid
    old_pid=$(cat "$PID_FILE")
    if kill -0 "$old_pid" 2>/dev/null; then
      ok "Proxy already running (PID $old_pid) on port $JXPROXY_PORT"
      return 0
    fi
    rm -f "$PID_FILE"
  fi

  info "Starting proxy (port $JXPROXY_PORT, provider: $JXPROXY_PROVIDER)..."

  JXPROXY_PORT="$JXPROXY_PORT" \
  JXPROXY_PROVIDER="$JXPROXY_PROVIDER" \
  ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
  OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}" \
  OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
  MODEL="${MODEL:-}" \
  MODEL_OPUS="${MODEL_OPUS:-}" \
  MODEL_SONNET="${MODEL_SONNET:-}" \
  MODEL_HAIKU="${MODEL_HAIKU:-}" \
  ENABLE_MODEL_THINKING="${ENABLE_MODEL_THINKING:-true}" \
  LD_PRELOAD="" \
  nohup ${JXPROXY_GLIBC_LD:+"$JXPROXY_GLIBC_LD"} "$PROXY_BINARY" > "$LOG_FILE" 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_FILE"

  for i in $(seq 1 15); do
    if curl -sf "http://127.0.0.1:$JXPROXY_PORT/health" > /dev/null 2>&1; then
      ok "Proxy started (PID $pid) on port $JXPROXY_PORT"
      return 0
    fi
    sleep 0.5
  done

  err "Proxy failed to start within 7.5 seconds"
  tail -20 "$LOG_FILE" 2>/dev/null || true
  return 1
}

stop_proxy() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      info "Stopping proxy (PID $pid)..."
      kill "$pid" 2>/dev/null || true
      for i in $(seq 1 10); do
        if ! kill -0 "$pid" 2>/dev/null; then
          ok "Proxy stopped"
          rm -f "$PID_FILE"
          return 0
        fi
        sleep 0.2
      done
      warn "Force killing proxy..."
      kill -9 "$pid" 2>/dev/null || true
      rm -f "$PID_FILE"
    else
      warn "Proxy PID $pid not running, removing stale PID file"
      rm -f "$PID_FILE"
    fi
  else
    warn "No proxy PID file found at $PID_FILE"
  fi
}

proxy_status() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      ok "Proxy is running (PID $pid) on port $JXPROXY_PORT"
      if curl -sf "http://127.0.0.1:$JXPROXY_PORT/health" > /dev/null 2>&1; then
        local health
        health=$(curl -sf "http://127.0.0.1:$JXPROXY_PORT/health")
        echo "  Health: $health"
      fi
      return 0
    fi
    warn "PID file exists but proxy is not running (stale)"
    return 1
  fi
  warn "Proxy is not running"
  return 1
}

# --- Actions ---

case "${1:-}" in
  --proxy-only)
    start_proxy
    exit $?
    ;;

  --proxy-stop)
    stop_proxy
    exit 0
    ;;

  --proxy-reuse)
    if ! proxy_status > /dev/null 2>&1; then
      warn "No proxy running — starting one..."
      "$0" --proxy-only
    fi
    shift 2>/dev/null || true
    ;;

  --status)
    proxy_status
    exit $?
    ;;

  --setup-api)
    echo ""
    echo "  jxproxy — API Key Setup"
    echo "  ──────────────────────────"
    echo "  Edit ~/.jxproxy/config.env directly, or paste keys here:"
    echo ""
    # Reuse the setup keys function from the installer
    SETUP_SCRIPT="$(dirname "$0")/install-jxproxy-termux.sh"
    SETUP_SCRIPT2="$DATA_DIR/api-setup.sh"
    if [ -f "$(dirname "$0")/install-jxproxy-termux.sh" ]; then
      # Extract the setup function inline
      echo "  Opening config file for editing..."
      echo "  Press Ctrl+X when done."
      echo ""
      sleep 1
      if command -v nano >/dev/null 2>&1; then
        nano "$CONFIG_FILE"
      else
        vi "$CONFIG_FILE"
      fi
    else
      if command -v nano >/dev/null 2>&1; then
        nano "$CONFIG_FILE"
      else
        vi "$CONFIG_FILE"
      fi
    fi
    echo ""
    echo "  Done. Config: $CONFIG_FILE"
    echo "  Restart jxproxy for changes to take effect."
    exit 0
    ;;
esac

# --- Default: Start proxy + CLI ---

# 1. Start the proxy if not already running
if ! proxy_status > /dev/null 2>&1; then
  start_proxy || {
    err "Could not start proxy. Check $LOG_FILE"
    exit 1
  }
fi

# 2. Launch the modified Claude Code CLI pointed at the proxy
if [ ! -x "$CLI_BINARY" ]; then
  err "CLI binary not found: $CLI_BINARY"
  err "Re-run the installer or place jxproxy-cli in $BIN_DIR"
  exit 1
fi

export ANTHROPIC_BASE_URL="http://127.0.0.1:$JXPROXY_PORT"
export ANTHROPIC_AUTH_TOKEN="$JXPROXY_AUTH_TOKEN"
export CLAUDE_CODE_AUTO_COMPACT_WINDOW="190000"
export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY="true"
export CLAUDE_CODE_VERIFY_PLAN="false"

info "Launching CLI (ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL)..."
echo ""

# Show progress dots while the binary loads (the exec replaces the shell)
{
  local dots=""
  for i in $(seq 1 30); do
    dots="${dots}."
    printf "\r  Loading CLI binary [%-30s] %d/30" "$dots" "$i"
    sleep 0.3
  done
  printf "\r  Loading CLI binary [██████████████████████████████] done\n"
} &
spinner_pid=$!

# Trap ensures dots stop even if exec fails
trap 'kill "$spinner_pid" 2>/dev/null; rm -f "$PID_FILE"' EXIT

run_via_glibc "$CLI_BINARY" "$@"

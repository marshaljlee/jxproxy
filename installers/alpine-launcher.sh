#!/bin/sh
#
# jxproxy — Alpine Linux Launcher
#
# Starts the proxy server and the modified Claude Code CLI on Alpine Linux,
# routing all Anthropic API traffic through the proxy.
#
# Alpine uses musl libc; jxproxy binaries are glibc-compiled. This launcher
# expects gcompat to be installed for transparent glibc ABI compatibility.
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
#

set -eu

# --- Paths ---

BIN_DIR="$(dirname "$0")"
DATA_DIR="${JXPROXY_DATA_DIR:-${HOME}/.jxproxy}"
CONFIG_FILE="$DATA_DIR/config.env"
PID_FILE="$DATA_DIR/proxy.pid"
LOG_FILE="$DATA_DIR/proxy.log"

# --- Colors ---

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
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
      [ "$key" = "${key#\#}" ] || continue
      [ -n "$key" ] || continue
      key="$(echo "$key" | tr -d ' ')"
      value="$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [ -n "$key" ] && export "$key=$value"
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

# --- Help ---

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<EOF
jxproxy — Alpine Linux — Claude Code with proxy routing, telemetry stripped

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

start_proxy() {
  if [ ! -x "$PROXY_BINARY" ]; then
    err "Proxy binary not found: $PROXY_BINARY"
    err "Re-run the installer or place jxproxy-proxy in $BIN_DIR"
    exit 1
  fi

  if [ -f "$PID_FILE" ]; then
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
  nohup "$PROXY_BINARY" > "$LOG_FILE" 2>&1 &
  pid=$!
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
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      ok "Proxy is running (PID $pid) on port $JXPROXY_PORT"
      if curl -sf "http://127.0.0.1:$JXPROXY_PORT/health" > /dev/null 2>&1; then
        echo "  Health: $(curl -sf "http://127.0.0.1:$JXPROXY_PORT/health")"
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

exec "$CLI_BINARY" "$@"

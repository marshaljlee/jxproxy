#!/bin/bash
#
# jxproxy — The combined launcher
#
# Starts the proxy server and the modified Claude Code CLI, routing all
# Anthropic API traffic through the proxy.
#
# Usage:
#   ./jxproxy                  # Start proxy + CLI
#   ./jxproxy --proxy-only     # Start proxy server only
#   ./jxproxy --proxy-reuse    # Use existing proxy, launch CLI only
#   ./jxproxy -- --help        # Pass flags through to Claude CLI
#
# Environment:
#   JXPROXY_PORT             — Proxy listen port (default: 5529)
#   JXPROXY_PROVIDER         — Provider backend (default: direct)
#   JXPROXY_DATA_DIR         — Config/data directory (default: ~/.jxproxy)
#   JXPROXY_CLI_BINARY       — Path to the CLI binary (default: auto-detect)
#   JXPROXY_PROXY_BINARY     — Path to the proxy binary (default: auto-detect)
#

set -euo pipefail

# --- Configuration ---

JXPROXY_PORT="${JXPROXY_PORT:-5529}"
JXPROXY_PROVIDER="${JXPROXY_PROVIDER:-direct}"
JXPROXY_DATA_DIR="${JXPROXY_DATA_DIR:-$HOME/.jxproxy}"
JXPROXY_PID_FILE="$JXPROXY_DATA_DIR/proxy.pid"
JXPROXY_LOG_FILE="$JXPROXY_DATA_DIR/proxy.log"
JXPROXY_CONFIG_FILE="$JXPROXY_DATA_DIR/config.env"

# Auto-detect binary paths relative to this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Look for jxproxy-cli first (new name), fall back to dist/jxproxy (old name, build output)
if [ -f "$SCRIPT_DIR/jxproxy-cli" ]; then
  JXPROXY_CLI_BINARY="${JXPROXY_CLI_BINARY:-$SCRIPT_DIR/jxproxy-cli}"
elif [ -f "$SCRIPT_DIR/../dist/jxproxy" ]; then
  JXPROXY_CLI_BINARY="${JXPROXY_CLI_BINARY:-$(cd "$SCRIPT_DIR/.." && pwd)/dist/jxproxy}"
else
  JXPROXY_CLI_BINARY="${JXPROXY_CLI_BINARY:-}"
fi

if [ -f "$SCRIPT_DIR/jxproxy-proxy" ]; then
  JXPROXY_PROXY_BINARY="${JXPROXY_PROXY_BINARY:-$SCRIPT_DIR/jxproxy-proxy}"
elif [ -f "$SCRIPT_DIR/../dist/jxproxy-proxy" ]; then
  JXPROXY_PROXY_BINARY="${JXPROXY_PROXY_BINARY:-$(cd "$SCRIPT_DIR/.." && pwd)/dist/jxproxy-proxy}"
else
  JXPROXY_PROXY_BINARY="${JXPROXY_PROXY_BINARY:-}"
fi

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

# --- Help ---

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<EOF
jxproxy — Claude Code with proxy routing, telemetry stripped, all features unlocked

Usage:
  jxproxy                  Start proxy + CLI
  jxproxy --proxy-only     Start proxy server only
  jxproxy --proxy-reuse    Connect to existing proxy, start CLI
  jxproxy --proxy-stop     Stop the running proxy
  jxproxy --status         Check proxy status
  jxproxy -- --help        Pass flags to Claude CLI
  jxproxy --help           Show this help

Environment:
  JXPROXY_PORT             Proxy port (default: 5529)
  JXPROXY_PROVIDER         Provider: direct, openrouter, openai, local
  ANTHROPIC_API_KEY        API key for direct Anthropic routing
  OPENROUTER_API_KEY       API key for OpenRouter routing
  MODEL, MODEL_OPUS, MODEL_SONNET, MODEL_HAIKU — Model routing

Config file: $JXPROXY_CONFIG_FILE
Data dir:    $JXPROXY_DATA_DIR
EOF
  exit 0
fi

# --- Ensure data directory ---

mkdir -p "$JXPROXY_DATA_DIR"

# --- Safe config loading ---
# Reads key=value pairs from config file, skipping comments and blank lines.
# Does NOT source the file — safe from malformed lines that would crash with set -e.

load_config() {
  if [ -f "$JXPROXY_CONFIG_FILE" ]; then
    while IFS='=' read -r key value; do
      # Skip comments and blank lines
      [[ "$key" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${key// /}" ]] && continue
      key="$(echo "$key" | tr -d ' ')"
      value="$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      if [ -n "$key" ]; then
        export "$key=$value"
      fi
    done < "$JXPROXY_CONFIG_FILE"
    info "Loaded config from $JXPROXY_CONFIG_FILE"
  fi
}

load_config

# --- Functions ---

# Ensure the proxy binary is available, building it if necessary
ensure_proxy_binary() {
  if [ -n "$JXPROXY_PROXY_BINARY" ] && [ -x "$JXPROXY_PROXY_BINARY" ]; then
    return 0
  fi

  # Try known locations
  if [ -x "$SCRIPT_DIR/jxproxy-proxy" ]; then
    JXPROXY_PROXY_BINARY="$SCRIPT_DIR/jxproxy-proxy"
    return 0
  fi

  local dist_proxy="$SCRIPT_DIR/../dist/jxproxy-proxy"
  if [ -x "$dist_proxy" ]; then
    JXPROXY_PROXY_BINARY="$dist_proxy"
    return 0
  fi

  # Try to build from source
  if [ -f "$SCRIPT_DIR/../proxy/server.ts" ] && command -v bun &>/dev/null; then
    info "Proxy binary not found, building from source..."
    (cd "$SCRIPT_DIR/.." && bun build ./proxy/server.ts --compile --target=bun --minify --bytecode --outfile ./dist/jxproxy-proxy) || {
      err "Failed to build proxy binary."
      return 1
    }
    if [ -x "$dist_proxy" ]; then
      JXPROXY_PROXY_BINARY="$dist_proxy"
      return 0
    fi
  fi

  err "Proxy binary not found and could not be built."
  err "Run 'bun run build:proxy' from the jxproxy source directory."
  return 1
}

start_proxy() {
  local binary="$1"

  if [ ! -x "$binary" ]; then
    err "Proxy binary not found: $binary"
    err "Build it with: bun run build:proxy"
    exit 1
  fi

  if [ -f "$JXPROXY_PID_FILE" ]; then
    local old_pid
    old_pid=$(cat "$JXPROXY_PID_FILE")
    if kill -0 "$old_pid" 2>/dev/null; then
      ok "Proxy already running (PID $old_pid) on port $JXPROXY_PORT"
      return 0
    fi
    rm -f "$JXPROXY_PID_FILE"
  fi

  info "Starting proxy (port $JXPROXY_PORT, provider: $JXPROXY_PROVIDER)..."

  JXPROXY_PORT="$JXPROXY_PORT" \
  JXPROXY_PROVIDER="$JXPROXY_PROVIDER" \
  ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
  OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}" \
  OPENCODE_API_KEY="${OPENCODE_API_KEY:-}" \
  OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
  OPENAI_BASE_URL="${OPENAI_BASE_URL:-}" \
  FALLBACK_PROVIDERS="${FALLBACK_PROVIDERS:-}" \
  LOCAL_LLM_BASE_URL="${LOCAL_LLM_BASE_URL:-}" \
  LOCAL_LLM_MODEL="${LOCAL_LLM_MODEL:-}" \
  MODEL="${MODEL:-}" \
  MODEL_OPUS="${MODEL_OPUS:-}" \
  MODEL_SONNET="${MODEL_SONNET:-}" \
  MODEL_HAIKU="${MODEL_HAIKU:-}" \
  ENABLE_MODEL_THINKING="${ENABLE_MODEL_THINKING:-true}" \
  nohup "$binary" > "$JXPROXY_LOG_FILE" 2>&1 &
  local pid=$!
  echo "$pid" > "$JXPROXY_PID_FILE"

  # Wait for proxy to be available
  for i in $(seq 1 30); do
    if curl -sf "http://127.0.0.1:$JXPROXY_PORT/health" > /dev/null 2>&1; then
      ok "Proxy started (PID $pid) on port $JXPROXY_PORT"
      return 0
    fi
    sleep 0.2
  done

  err "Proxy failed to start within 6 seconds"
  tail -20 "$JXPROXY_LOG_FILE" 2>/dev/null || true
  return 1
}

stop_proxy() {
  if [ -f "$JXPROXY_PID_FILE" ]; then
    local pid
    pid=$(cat "$JXPROXY_PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      info "Stopping proxy (PID $pid)..."
      kill "$pid" 2>/dev/null || true
      for i in $(seq 1 10); do
        if ! kill -0 "$pid" 2>/dev/null; then
          ok "Proxy stopped"
          rm -f "$JXPROXY_PID_FILE"
          return 0
        fi
        sleep 0.2
      done
      warn "Force killing proxy..."
      kill -9 "$pid" 2>/dev/null || true
      rm -f "$JXPROXY_PID_FILE"
    else
      warn "Proxy PID $pid not running, removing stale PID file"
      rm -f "$JXPROXY_PID_FILE"
    fi
  else
    warn "No proxy PID file found at $JXPROXY_PID_FILE"
  fi
}

proxy_status() {
  if [ -f "$JXPROXY_PID_FILE" ]; then
    local pid
    pid=$(cat "$JXPROXY_PID_FILE")
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
    ensure_proxy_binary || exit 1
    start_proxy "$JXPROXY_PROXY_BINARY"
    exit $?
    ;;

  --proxy-stop)
    stop_proxy
    exit 0
    ;;

  --proxy-reuse)
    if ! proxy_status > /dev/null 2>&1; then
      warn "No proxy running — starting one..."
      # Recurse with --proxy-only in background
      "$0" --proxy-only
    fi
    shift  # Remove --proxy-reuse from args
    # Falls through to launch CLI
    ;;

  --status)
    proxy_status
    exit $?
    ;;
esac

# --- Default: Start proxy + CLI ---

# 1. Ensure proxy binary exists, then start if not already running
ensure_proxy_binary || exit 1
if ! proxy_status > /dev/null 2>&1; then
  start_proxy "$JXPROXY_PROXY_BINARY" || {
    err "Could not start proxy. Check $JXPROXY_LOG_FILE"
    exit 1
  }
fi

# 2. Launch the modified Claude Code CLI pointed at the proxy
if [ -z "$JXPROXY_CLI_BINARY" ]; then
  # Try to build it
  if [ -f "$SCRIPT_DIR/../dist/jxproxy" ]; then
    JXPROXY_CLI_BINARY="$SCRIPT_DIR/../dist/jxproxy"
  else
    err "CLI binary not found. Build with: bun run build"
    exit 1
  fi
fi

if [ ! -x "$JXPROXY_CLI_BINARY" ]; then
  err "CLI binary not executable: $JXPROXY_CLI_BINARY"
  exit 1
fi

export ANTHROPIC_BASE_URL="http://127.0.0.1:$JXPROXY_PORT"
export CLAUDE_CODE_AUTO_COMPACT_WINDOW="190000"
export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY="true"
export CLAUDE_CODE_VERIFY_PLAN="false"

# Set auth token so Claude Code sends it as x-api-key to the proxy
export ANTHROPIC_AUTH_TOKEN="jxproxy"

info "Launching CLI (ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL)..."
echo ""

exec "$JXPROXY_CLI_BINARY" "$@"

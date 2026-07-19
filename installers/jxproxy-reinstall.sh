#!/data/data/com.termux/files/usr/bin/bash
#
# jxproxy — Uninstall & Reinstall (fresh test)
#
# Wipes everything, then reinstalls from GitHub.
# Run this to test the full install flow.
#
# Usage:
#   bash jxproxy-reinstall.sh
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
echo -e "${BOLD}═══ jxproxy — Uninstall & Reinstall ═══${NC}"
echo ""

# ── UNINSTALL ───────────────────────────────────────────────

echo -e "${YELLOW}Uninstalling current installation...${NC}"

# Stop proxy if running
if [ -f "$HOME/.jxproxy/proxy.pid" ]; then
  pid=$(cat "$HOME/.jxproxy/proxy.pid" 2>/dev/null || echo "")
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    echo "  ✓ Stopped proxy (PID $pid)"
  fi
fi

# Remove binaries
for f in "$HOME/.local/bin/jxproxy" "$HOME/.local/bin/jxproxy-cli" "$HOME/.local/bin/jxproxy-proxy" "$HOME/.local/bin/claude"; do
  if [ -e "$f" ] || [ -L "$f" ]; then
    rm -f "$f" && echo "  ✓ Removed $f"
  fi
done

# Remove config + logs
if [ -d "$HOME/.jxproxy" ]; then
  rm -rf "$HOME/.jxproxy" && echo "  ✓ Removed ~/.jxproxy/"
fi

# Remove env file if exists
if [ -f "$HOME/.jxproxy_env" ]; then
  rm -f "$HOME/.jxproxy_env" && echo "  ✓ Removed ~/.jxproxy_env"
fi

# Clean shell configs
for rc in "$HOME/.bashrc" "$HOME/.profile"; do
  if [ -f "$rc" ]; then
    sed -i '/jxproxy/d' "$rc" 2>/dev/null && echo "  ✓ Cleaned $rc"
  fi
done

# Restore official claude if renamed
if [ -f "/data/data/com.termux/files/usr/bin/claude-official" ]; then
  mv "/data/data/com.termux/files/usr/bin/claude-official" "/data/data/com.termux/files/usr/bin/claude" 2>/dev/null
  echo "  ✓ Restored /usr/bin/claude"
fi

echo ""
echo -e "${GREEN}Uninstall complete.${NC}"
echo ""
echo -e "${CYAN}Now reinstalling...${NC}"
echo ""

# ── REINSTALL ───────────────────────────────────────────────

# Check for --from-dist
FROM_DIST=""
if [ -n "${1:-}" ] && [ "$1" = "--from-dist" ]; then
  FROM_DIST="${2:-}"
  if [ -z "$FROM_DIST" ]; then
    echo "Usage: $0 --from-dist /path/to/binaries"
    exit 1
  fi
  echo "Using local dist: $FROM_DIST"
fi

# Run installer
if [ -n "$FROM_DIST" ]; then
  curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/install-jxproxy-termux.sh | bash -s -- "--from-dist=$FROM_DIST"
else
  curl -fsSL https://raw.githubusercontent.com/marshaljlee/jxproxy/main/installers/install-jxproxy-termux.sh | bash
fi

echo ""
echo -e "${GREEN}Reinstall complete. Reload shell and run 'claude'.${NC}"
echo "  source ~/.bashrc"
echo "  claude"

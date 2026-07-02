#!/bin/bash
#
# jxproxy Bootstrap Script
#
# Fetches the free-code base source and initializes the build environment.
# This gives us the Claude Code TypeScript source with telemetry already
# stripped and feature flags exposed.
#
# Usage:
#   bun run bootstrap       # Fetch free-code base + install deps
#   bun run bootstrap --min # Skip full history, shallow clone only
#

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# --- Configuration ---
FREE_CODE_REPO="https://github.com/freecodexyz/free-code.git"
SOURCE_DIR="$ROOT_DIR/src"
TEMPDIR=$(mktemp -d)

cleanup() { rm -rf "$TEMPDIR"; }
trap cleanup EXIT

echo "=== jxproxy Bootstrap ==="
echo ""

# --- Pre-flight: Check Bun version ---

MIN_BUN="1.3.11"
BUN_VER=$(bun --version 2>/dev/null || echo "0")
if [ "$(printf '%s\n' "$MIN_BUN" "$BUN_VER" | sort -V | head -n1)" != "$MIN_BUN" ]; then
  echo "  ✗ Bun ${BUN_VER} is too old. jxproxy requires Bun ${MIN_BUN}+."
  echo "  Upgrade with: curl -fsSL https://bun.sh/install | bash"
  exit 1
fi

echo "  ✓ bun ${BUN_VER}"

# --- Phase 1: Fetch free-code base source ---

echo "[1/4] Fetching free-code base source..."

if [ -d "$SOURCE_DIR" ] && [ -f "$SOURCE_DIR/entrypoints/cli.tsx" ]; then
	  echo "  ✓ Source directory already exists (bundled in repo or from prior bootstrap)"
	  echo "    Found: $SOURCE_DIR/entrypoints/cli.tsx"
	  echo "    Run 'bun run patch' to re-apply patches."
	  echo "    To re-fetch from external source, delete src/ and re-run bootstrap."
	else
	  echo "  No local source found — fetching from ${FREE_CODE_REPO}..."
	  if [ "${1:-}" = "--min" ]; then
	    git clone --depth 1 "$FREE_CODE_REPO" "$TEMPDIR/free-code"
	  else
	    echo "  Cloning full repository (use --min for shallow clone)..."
	    git clone "$FREE_CODE_REPO" "$TEMPDIR/free-code"
	  fi

  # Copy source, excluding test files and CI config
  cp -r "$TEMPDIR/free-code/src" "$ROOT_DIR/"
  cp "$TEMPDIR/free-code/package.json" "$ROOT_DIR/package.base.json" 2>/dev/null || true
  cp "$TEMPDIR/free-code/bun.lock" "$ROOT_DIR/" 2>/dev/null || true

  echo "  ✓ Source fetched to $SOURCE_DIR"
fi

# --- Phase 2: Install dependencies ---

echo "[2/4] Installing dependencies..."

if [ -f "$ROOT_DIR/bun.lock" ]; then
  bun install --frozen-lockfile 2>/dev/null || bun install
else
  bun install
fi

echo "  ✓ Dependencies installed"

# --- Phase 3: Apply jxproxy patches ---

echo "[3/4] Applying jxproxy patches..."
bash "$ROOT_DIR/scripts/patch-source.sh"
echo ""

# --- Phase 4: Verify build readiness ---

echo "[4/4] Verifying build readiness..."

ERRORS=0

if [ ! -f "$SOURCE_DIR/entrypoints/cli.tsx" ]; then
  echo "  ✗ Missing: src/entrypoints/cli.tsx"
  ERRORS=$((ERRORS + 1))
fi

if ! command -v bun &>/dev/null; then
  echo "  ✗ Missing: bun runtime (install with 'curl -fsSL https://bun.sh/install | bash')"
  ERRORS=$((ERRORS + 1))
fi

	if [ $ERRORS -eq 0 ]; then
  echo "  ✓ Ready to build! Run 'bun run build' to compile."
else
  echo "  ✗ $ERRORS error(s) — fix before building"
  exit 1
fi

echo ""
echo "=== Bootstrap complete ==="

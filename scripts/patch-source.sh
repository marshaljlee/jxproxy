#!/bin/bash
#
# jxproxy — Patch Application Script
#
# Applies all jxproxy patches from patches/*.patch to the src/ directory.
# This is the standalone script called by `bun run patch`.
#
# Usage:
#   bash scripts/patch-source.sh           # Apply all patches
#   bash scripts/patch-source.sh --check   # Check if patches are applied
#
# Dependencies:
#   - git (for git apply)
#   - src/ directory must exist (bootstrap must have run)
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/src"
PATCH_DIR="$ROOT_DIR/patches"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info()  { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
err()   { echo -e "${RED}✗${NC} $1" >&2; }

# --- Preflight ---

if [ ! -d "$SOURCE_DIR" ]; then
  err "Source directory not found at $SOURCE_DIR"
  err "Run 'bun run bootstrap' first to fetch the base source."
  exit 1
fi

if [ ! -d "$PATCH_DIR" ]; then
  err "Patches directory not found at $PATCH_DIR"
  exit 1
fi

# --- Gather patches ---

PATCH_FILES=()
while IFS= read -r -d '' patch; do
  PATCH_FILES+=("$patch")
done < <(find "$PATCH_DIR" -maxdepth 1 -name '*.patch' -print0 2>/dev/null || true)
IFS=$'\n' PATCH_FILES=($(sort <<<"${PATCH_FILES[*]}")); unset IFS

if [ ${#PATCH_FILES[@]} -eq 0 ]; then
  warn "No .patch files found in $PATCH_DIR"
  exit 0
fi

# --- Check mode ---

if [ "${1:-}" = "--check" ]; then
  all_applied=true
  for patch in "${PATCH_FILES[@]}"; do
    if (cd "$SOURCE_DIR" && git apply --check "$patch" 2>/dev/null); then
      warn "$(basename "$patch") — NOT applied"
      all_applied=false
    else
      info "$(basename "$patch") — applied"
    fi
  done
  $all_applied
  exit $?
fi

# --- Apply patches ---

echo "  Applying jxproxy patches to $SOURCE_DIR..."
echo ""

APPIED=0
SKIPPED=0
FAILED=0

for patch in "${PATCH_FILES[@]}"; do
  name="$(basename "$patch")"
  
  # Try to apply — git apply will fail if already applied
  if (cd "$SOURCE_DIR" && git apply "$patch" 2>/dev/null); then
    info "$name — applied"
    APPIED=$((APPIED + 1))
  else
    # Check if it's already applied (reject) or a real conflict
    if (cd "$SOURCE_DIR" && git apply --reverse --check "$patch" 2>/dev/null); then
      info "$name — already applied, skipped"
      SKIPPED=$((SKIPPED + 1))
    else
      err "$name — FAILED to apply (conflict)"
      err "  Manual review needed."
      FAILED=$((FAILED + 1))
    fi
  fi
done

echo ""
echo "  Results: $APPIED applied, $SKIPPED skipped, $FAILED failed"

if [ $FAILED -gt 0 ]; then
  exit 1
fi

#!/bin/bash
set -euo pipefail

# Build universal macOS binary for npm distribution
#
# Produces a fat binary containing both arm64 and x86_64 slices,
# then copies it to npm/bin/ for packaging.
#
# Usage:
#   ./scripts/build-universal.sh          # Build and copy to npm/bin/
#   ./scripts/build-universal.sh --check  # Also verify the result with lipo -info

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build"
NPM_BIN="$REPO_ROOT/npm/bin"

PRODUCT="reminders"

echo "==> Building $PRODUCT for arm64..."
swift build -c release --arch arm64

echo "==> Building $PRODUCT for x86_64..."
swift build -c release --arch x86_64

ARM64_BIN="$BUILD_DIR/arm64-apple-macosx/release/$PRODUCT"
X86_64_BIN="$BUILD_DIR/x86_64-apple-macosx/release/$PRODUCT"

if [ ! -f "$ARM64_BIN" ]; then
  echo "ERROR: arm64 binary not found at $ARM64_BIN" >&2
  exit 1
fi

if [ ! -f "$X86_64_BIN" ]; then
  echo "ERROR: x86_64 binary not found at $X86_64_BIN" >&2
  exit 1
fi

echo "==> Creating universal binary..."
mkdir -p "$NPM_BIN"
lipo -create "$ARM64_BIN" "$X86_64_BIN" -output "$NPM_BIN/$PRODUCT"
chmod +x "$NPM_BIN/$PRODUCT"

echo "==> Universal binary created at $NPM_BIN/$PRODUCT"

if [ "${1:-}" = "--check" ]; then
  echo "==> Verifying:"
  lipo -info "$NPM_BIN/$PRODUCT"
  ls -lh "$NPM_BIN/$PRODUCT"
fi

echo "==> Done."

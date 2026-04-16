#!/bin/sh
set -eu
# Resolve Pimeleon version for the current platform and context.
# Wraps shared/scripts/get-next-version.sh for CI/CD.

PLATFORM="${1:-}"
[ -n "$PLATFORM" ] || { echo "Error: platform is required" >&2; exit 1; }

# Install dependencies if missing (for alpine/CI environments)
if ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    apk add --no-cache curl git jq >/dev/null 2>&1 || true
fi

# Determine version
git fetch --quiet origin "+refs/tags/*:refs/tags/*" 2>/dev/null || true
SCRIPT_DIR="$(dirname "$0")"
VERSION=$(sh "${SCRIPT_DIR}/../../shared/scripts/get-next-version.sh" "$PLATFORM")

echo "$VERSION"

#!/bin/bash
set -euo pipefail

# Resolve Platform and Version metadata for the build.
#
# Inputs (env):
#   INPUT_PLATFORM   — target platform slug (e.g. rpi3-bookworm)
#   INPUT_VERSION    — explicit version override (may be empty)
#   REGISTRY         — container registry hostname (e.g. ghcr.io)
#   GITHUB_REPOSITORY — owner/repo (injected automatically by GitHub Actions)
#
# Outputs (GITHUB_OUTPUT):
#   target_platform, version, needs_rebuild, builder_image, ab2p_image

PLATFORM="${INPUT_PLATFORM:-rpi3-bookworm}"
VERSION="${INPUT_VERSION:-}"

if [ -z "$VERSION" ]; then
    chmod +x ./shared/scripts/get-next-version.sh
    VERSION=$(./shared/scripts/get-next-version.sh "$PLATFORM")
fi

# Rebuild on minor version bump or when triggered manually (no explicit version)
if [ -z "${INPUT_VERSION:-}" ]; then
    NEEDS_REBUILD=true
else
    BASE_VERSION=$(cat "apps/${PLATFORM}/VERSION" 2>/dev/null || echo "0.1.0")
    BASE_MINOR=$(echo "$BASE_VERSION" | cut -d. -f2)
    NEW_MINOR=$(echo "$VERSION"       | cut -d. -f2)
    if [ "$NEW_MINOR" -gt "$BASE_MINOR" ]; then
        NEEDS_REBUILD=true
    else
        NEEDS_REBUILD=false
    fi
fi

BUILDER_IMAGE="${REGISTRY}/${GITHUB_REPOSITORY}/builder:latest"
AB2P_IMAGE="${REGISTRY}/${GITHUB_REPOSITORY}/adblock2privoxy:latest"

{
    echo "target_platform=${PLATFORM}"
    echo "version=${VERSION}"
    echo "needs_rebuild=${NEEDS_REBUILD}"
    echo "builder_image=${BUILDER_IMAGE}"
    echo "ab2p_image=${AB2P_IMAGE}"
} >> "$GITHUB_OUTPUT"

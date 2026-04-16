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

[ -n "$VERSION" ] || { echo "[ERROR] INPUT_VERSION is required — must be provided by GitLab trigger or workflow_dispatch input" >&2; exit 1; }

NEEDS_REBUILD=true

BUILDER_IMAGE="${REGISTRY}/${GITHUB_REPOSITORY}/builder:latest"
AB2P_IMAGE="${REGISTRY}/${GITHUB_REPOSITORY}/adblock2privoxy:latest"

{
    echo "target_platform=${PLATFORM}"
    echo "version=${VERSION}"
    echo "needs_rebuild=${NEEDS_REBUILD}"
    echo "builder_image=${BUILDER_IMAGE}"
    echo "ab2p_image=${AB2P_IMAGE}"
} >> "$GITHUB_OUTPUT"

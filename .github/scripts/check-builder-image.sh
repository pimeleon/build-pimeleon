#!/bin/bash
set -euo pipefail

# Check whether the builder image already exists in GHCR.
#
# Inputs (env):
#   BUILDER_IMAGE — full image reference (registry/repo/builder:tag)
#
# Outputs (GITHUB_OUTPUT):
#   exists — true | false

if docker manifest inspect "${BUILDER_IMAGE}" >/dev/null 2>&1; then
    echo "exists=true" >> "$GITHUB_OUTPUT"
else
    echo "exists=false" >> "$GITHUB_OUTPUT"
fi

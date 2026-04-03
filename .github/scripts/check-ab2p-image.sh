#!/bin/bash
set -euo pipefail

# Verify adblock2privoxy image exists in GHCR.
#
# Inputs (env):
#   AB2P_IMAGE — full image reference (registry/repo/adblock2privoxy:tag)

if ! docker manifest inspect "${AB2P_IMAGE}" >/dev/null 2>&1; then
    echo "[ERROR] adblock2privoxy image missing in GHCR. GitLab sync failed or was not triggered."
    exit 1
fi

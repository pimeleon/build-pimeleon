#!/bin/bash
set -euo pipefail

# Build the Pimeleon builder image and push it to GHCR.
#
# Inputs (env):
#   BUILDER_IMAGE — full image reference to build and push
#   AB2P_IMAGE    — adblock2privoxy image reference passed as a build-arg

docker build \
    --cache-from "${BUILDER_IMAGE}" \
    --build-arg AB2P_IMAGE="${AB2P_IMAGE}" \
    -t "${BUILDER_IMAGE}" \
    -f shared/containers/builder/Dockerfile .

docker push "${BUILDER_IMAGE}"

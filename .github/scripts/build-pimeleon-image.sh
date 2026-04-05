#!/bin/bash
set -euo pipefail

# Run the Pimeleon image build inside a privileged builder container.
#
# Inputs (env):
#   BUILDER_IMAGE              — builder container image to run
#   TARGET_PLATFORM            — platform slug (e.g. rpi3-bookworm)
#   VERSION                    — Pimeleon release version
#   PIMELEON_APPS_GITHUB_TOKEN — GitHub token for fetching pimeleon-apps packages
#   GITHUB_WORKSPACE           — injected automatically by GitHub Actions

mkdir -p output cache

docker run --rm --privileged \
    -v /dev:/dev:rw \
    -v "${GITHUB_WORKSPACE}/shared/scripts:/scripts" \
    -v "${GITHUB_WORKSPACE}/shared/configs:/configs" \
    -v "${GITHUB_WORKSPACE}/shared/ansible:/ansible" \
    -v "${GITHUB_WORKSPACE}/output:/output" \
    -v "${GITHUB_WORKSPACE}/cache:/cache" \
    -e CI=true \
    -e CACHE_DIR=/cache \
    -e OUTPUT_DIR=/output \
    -e TARGET_PLATFORM="${TARGET_PLATFORM}" \
    -e PIMELEON_VERSION="${VERSION}" \
    -e PIMELEON_PROFILE=production \
    -e PIMELEON_APPS_SOURCE=github \
    -e PIMELEON_APPS_GITHUB_TOKEN="${PIMELEON_APPS_GITHUB_TOKEN}" \
    -e BUILDER_UID="${BUILDER_UID:-1001}" \
    "${BUILDER_IMAGE}" \
    /scripts/build.sh

#!/bin/bash
set -euo pipefail

# Run the Pimeleon image build inside a privileged builder container.
#
# Inputs (env):
#   BUILDER_IMAGE              — builder container image to run
#   TARGET_PLATFORM            — platform slug (e.g. rpi3-bookworm)
#   VERSION                    — Pimeleon release version
#   PIMELEON_APPS_GITHUB_TOKEN — GitHub token for GHCR authentication
#   GITHUB_WORKSPACE           — injected automatically by GitHub Actions
#   GITHUB_ACTOR               — injected automatically by GitHub Actions

mkdir -p output cache

# Pull pimeleon-apps artifacts from GHCR and extract for use in the builder container.
# The builder container has no Docker socket, so extraction must happen on the host.
APPS_IMAGE="ghcr.io/pimeleon/pimeleon-apps/builder-armhf:latest"
echo "[INFO] Authenticating to GHCR"
echo "${PIMELEON_APPS_GITHUB_TOKEN}" | docker login ghcr.io -u "${GITHUB_ACTOR}" --password-stdin
echo "[INFO] Pulling pimeleon-apps: ${APPS_IMAGE}"
docker pull "${APPS_IMAGE}"
mkdir -p "${GITHUB_WORKSPACE}/cache/pimeleon-apps"
APPS_CID=$(docker create "${APPS_IMAGE}")
docker cp "${APPS_CID}:/output/." "${GITHUB_WORKSPACE}/cache/pimeleon-apps/"
docker rm "${APPS_CID}"
echo "[INFO] pimeleon-apps artifacts extracted to cache/pimeleon-apps/"

docker run --rm --privileged \
    -v /dev:/dev:rw \
    -v "${GITHUB_WORKSPACE}/shared/scripts:/scripts" \
    -v "${GITHUB_WORKSPACE}/shared/configs:/configs" \
    -v "${GITHUB_WORKSPACE}/shared/ansible:/ansible" \
    -v "${GITHUB_WORKSPACE}/output:/output" \
    -v "${GITHUB_WORKSPACE}/cache:/cache" \
    -v "${GITHUB_WORKSPACE}/cache/pimeleon-apps:/workspace/registry-apps:ro" \
    -e CI=true \
    -e CACHE_DIR=/cache \
    -e OUTPUT_DIR=/output \
    -e TARGET_PLATFORM="${TARGET_PLATFORM}" \
    -e PIMELEON_VERSION="${VERSION}" \
    -e PIMELEON_PROFILE=production \
    -e PIMELEON_APPS_SOURCE=github \
    -e PIMELEON_APPS_LOCAL_PATH=/workspace/registry-apps \
    -e BUILDER_UID="${BUILDER_UID:-1001}" \
    "${BUILDER_IMAGE}" \
    /scripts/build.sh

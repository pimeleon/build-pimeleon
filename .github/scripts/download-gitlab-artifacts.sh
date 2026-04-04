#!/bin/bash
set -euo pipefail

# Download build artifacts (image + metadata) from the GitLab package registry.
# Reuses existing .gitlab/scripts helpers by overriding their CI_ env vars.
#
# Inputs (env):
#   GITLAB_API_V4_URL — GitLab API base URL
#   GITLAB_PROJECT_ID — numeric project ID (13 for build-pimeleon)
#   GITLAB_FETCH_TOKEN      — read-only personal access token
#   PLATFORM          — target platform slug (e.g. rpi3-bookworm)
#   VERSION           — Pimeleon release version

mkdir -p output

PACKAGE_VERSION="${PLATFORM}-v${VERSION}"
echo "Downloading artifacts for ${PACKAGE_VERSION} from GitLab..."

CI_API_V4_URL="${GITLAB_API_V4_URL}" \
CI_PROJECT_ID="${GITLAB_PROJECT_ID}" \
CI_JOB_TOKEN="${GITLAB_FETCH_TOKEN}" \
sh .gitlab/scripts/download-package-image.sh "${PACKAGE_VERSION}" "output"

CI_API_V4_URL="${GITLAB_API_V4_URL}" \
CI_PROJECT_ID="${GITLAB_PROJECT_ID}" \
CI_JOB_TOKEN="${GITLAB_FETCH_TOKEN}" \
sh .gitlab/scripts/download-package-metadata.sh "${PACKAGE_VERSION}" "output/${PLATFORM}-v${VERSION}.img.metadata.json"

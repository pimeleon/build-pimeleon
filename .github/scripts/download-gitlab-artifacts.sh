#!/bin/bash
set -euo pipefail

# Download build artifacts (image + metadata) from the GitLab package registry.
#
# Inputs (env):
#   GITLAB_API_V4_URL  — GitLab API base URL
#   GITLAB_PROJECT_ID  — numeric project ID (13 for build-pimeleon)
#   GITLAB_DEPLOY_TOKEN | GITLAB_TOKEN — read-only personal access token
#   PLATFORM           — target platform slug (e.g. rpi3-bookworm)
#   VERSION            — Pimeleon release version

SCRIPT_DIR="$(dirname "$0")"

# Map GitHub Actions env vars to lib-api.sh expected variable names
export CI_API_V4_URL="${GITLAB_API_V4_URL:-https://gitlab.pirouter.dev/api/v4}"
export CI_PROJECT_ID="${GITLAB_PROJECT_ID:-13}"
export GITLAB_TOKEN="${GITLAB_DEPLOY_TOKEN:-${GITLAB_TOKEN:-}}"

. "${SCRIPT_DIR}/../../shared/scripts/lib-api.sh"

mkdir -p output

PACKAGE_VERSION="${PLATFORM}-v${VERSION}"
echo "Downloading artifacts for ${PACKAGE_VERSION} from GitLab..."

package_id=$(gitlab_package_id "${PACKAGE_VERSION}")

files_body=$(gitlab_api_get "/projects/${GITLAB_PROJECT}/packages/${package_id}/package_files")

# Download .img.xz (required)
img_file=$(printf '%s' "${files_body}" | \
    jq -r '[.[] | .file_name | select(endswith(".img.xz"))] | first // empty')
if [ -n "${img_file}" ]; then
    echo "[INFO] Downloading ${img_file}..."
    gitlab_download \
        "${GITLAB_API_URL}/projects/${GITLAB_PROJECT}/packages/generic/pimeleon/${PACKAGE_VERSION}/${img_file}" \
        "output/${img_file}"
else
    echo "[ERROR] No .img.xz artifact found for ${PACKAGE_VERSION}" >&2
    exit 1
fi

# Download metadata (optional)
meta_file=$(printf '%s' "${files_body}" | \
    jq -r '[.[] | .file_name | select(endswith(".metadata.json"))] | first // empty')
if [ -n "${meta_file}" ]; then
    echo "[INFO] Downloading ${meta_file}..."
    gitlab_download \
        "${GITLAB_API_URL}/projects/${GITLAB_PROJECT}/packages/generic/pimeleon/${PACKAGE_VERSION}/${meta_file}" \
        "output/${meta_file}" || true
fi

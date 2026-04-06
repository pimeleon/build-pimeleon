#!/bin/sh
set -eu

# Upload Pimeleon image artifacts to the GitLab Generic Packages registry.
#
# Inputs: TARGET_PLATFORM, GITLAB_DEPLOY_TOKEN, CI_API_V4_URL, CI_PROJECT_ID

apk add --no-cache curl git jq >/dev/null 2>&1 || true

SCRIPT_DIR="$(dirname "$0")"
. "${SCRIPT_DIR}/../../shared/scripts/lib-api.sh"

if [ -n "${CI_COMMIT_TAG:-}" ]; then
    PACKAGE_VERSION="${CI_COMMIT_TAG}"
else
    [ -n "${PIMELEON_VERSION:-}" ] || {
        echo "[ERROR] PIMELEON_VERSION is not set. Run .gitlab/scripts/detect-platform.sh first."
        exit 1
    }
    PACKAGE_VERSION="${TARGET_PLATFORM}-v${PIMELEON_VERSION}"
fi

echo "[INFO] Uploading artifacts for package version: ${PACKAGE_VERSION}"

# Check for new artifacts
if [ -z "$(ls -A output/*.img.xz 2>/dev/null)" ]; then
    if sh .gitlab/scripts/check-package-exists.sh "${PACKAGE_VERSION}"; then
        echo "[INFO] Package ${PACKAGE_VERSION} already exists in the registry and no fresh artifacts were produced. Skipping upload."
        exit 0
    fi

    status=$?
    if [ "${status}" -ne 1 ]; then
        exit "${status}"
    fi

    echo "[ERROR] No .img.xz artifacts found in output/. Build likely failed."
    exit 1
fi

# We have fresh artifacts, so delete existing package version from registry if it exists
# to ensure we don't end up with conflicting files or incorrect metadata.
echo "[INFO] Fresh artifacts found. Deleting existing package ${PACKAGE_VERSION} if it exists..."
sh .gitlab/scripts/delete-package.sh "${PACKAGE_VERSION}" || { echo "[WARN] Package deletion failed, attempting upload anyway..." ; }

# Upload artifacts
for file in output/pimeleon-*.img.xz output/*.img.metadata.json output/*.sha256; do
    if [ -f "$file" ]; then
        echo "[INFO] Uploading $(basename "$file")..."
        gitlab_api_put \
            "/projects/${GITLAB_PROJECT}/packages/generic/pimeleon/${PACKAGE_VERSION}/$(basename "$file")" \
            "$file"
        echo "[INFO] Successfully uploaded $(basename "$file")"
    fi
done

echo "[SUCCESS] All artifacts uploaded to registry."

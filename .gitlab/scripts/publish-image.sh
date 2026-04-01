#!/bin/sh
set -eu

# Install dependencies needed for version calculation and API requests
apk add --no-cache curl git >/dev/null 2>&1 || true

# Upload Pimeleon image artifacts to the GitLab Generic Packages registry.
# If the image already exists (IMAGE_EXISTS=true), it skips the network operations.
#
# Inputs: IMAGE_EXISTS, PACKAGE_VERSION (from check:image dotenv), TARGET_PLATFORM,
#         CI_JOB_TOKEN, CI_API_V4_URL, CI_PROJECT_ID

IMAGE_EXISTS="${IMAGE_EXISTS:-false}"

# PACKAGE_VERSION comes from check:image dotenv artifact; compute it as fallback
if [ -z "${PACKAGE_VERSION:-}" ]; then
    SCRIPTS_DIR="./shared/scripts"
    [ ! -f "./scripts/build.sh" ] || SCRIPTS_DIR="./scripts"
    chmod +x "${SCRIPTS_DIR}/get-next-version.sh"
    VERSION=$("${SCRIPTS_DIR}/get-next-version.sh" "${TARGET_PLATFORM}")
    PACKAGE_VERSION="${TARGET_PLATFORM}-v${VERSION}"
    echo "[INFO] PACKAGE_VERSION not injected via dotenv, computed: ${PACKAGE_VERSION}"
fi

if [ "$IMAGE_EXISTS" = "true" ]; then
    echo "[INFO] Image version '${PACKAGE_VERSION}' confirmed in registry."
    echo "[INFO] Skipping upload operations to optimize network usage."
    mkdir -p output
    echo "Registry: ${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages" > output/registry_link.txt
    exit 0
fi

echo "[INFO] Image missing from registry. Starting upload of local artifacts..."

if [ -z "$(ls -A output/*.img.xz 2>/dev/null)" ]; then
    echo "[ERROR] No .img.xz artifacts found in output/. Build likely failed."
    exit 1
fi

# Upload logic
# We use -w to check the HTTP status code because -f doesn't give us the response body on failure
for file in output/pimeleon-*.img.xz output/*.sha256; do
    if [ -f "$file" ]; then
        echo "[INFO] Uploading $(basename "$file")..."

        HTTP_RESPONSE=$(curl -s -k -w "\n%{http_code}" \
                --header "JOB-TOKEN: $CI_JOB_TOKEN" \
                --upload-file "$file" \
            "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/pimeleon/${PACKAGE_VERSION}/$(basename "$file")")

        STATUS=$(echo "$HTTP_RESPONSE" | tail -1)

        if [ "$STATUS" != "201" ] && [ "$STATUS" != "200" ]; then
            echo "[ERROR] Upload of $(basename "$file") failed with HTTP ${STATUS}"
            echo "[DEBUG] Response body: $(echo "$HTTP_RESPONSE" | sed '$d')"
            exit 1
        fi
        echo "[INFO] Successfully uploaded $(basename "$file")"
    fi
done

echo "[SUCCESS] All artifacts uploaded to registry."

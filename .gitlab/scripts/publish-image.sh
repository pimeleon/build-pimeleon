#!/bin/sh
set -eu

# Upload Pimeleon image artifacts to the GitLab Generic Packages registry.
#
# Inputs: TARGET_PLATFORM, CI_JOB_TOKEN, CI_API_V4_URL, CI_PROJECT_ID

PACKAGE_VERSION=$(sh .gitlab/scripts/resolve-version.sh package "${TARGET_PLATFORM}")

echo "[INFO] Uploading artifacts for package version: ${PACKAGE_VERSION}"

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

# Upload logic
# We use -w to check the HTTP status code because -f doesn't give us the response body on failure
for file in output/pimeleon-*.img.xz output/*.img.metadata.json output/*.sha256; do
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

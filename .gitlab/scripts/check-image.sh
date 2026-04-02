#!/bin/sh
set -eu

# Install dependencies needed for version calculation and API requests
apk add --no-cache curl git >/dev/null 2>&1 || true
git fetch origin --tags 2>/dev/null || true

# Check if the Pimeleon image for this version already exists in the registry
# Uses GitLab Generic Packages API: https://docs.gitlab.com/ee/api/packages.html

if [ -n "${CI_COMMIT_TAG:-}" ]; then
    PACKAGE_VERSION="${CI_COMMIT_TAG}"
else
    SCRIPTS_DIR="./shared/scripts"
    [ ! -f "./scripts/build.sh" ] || SCRIPTS_DIR="./scripts"
    chmod +x "${SCRIPTS_DIR}/get-next-version.sh"
    VERSION=$("${SCRIPTS_DIR}/get-next-version.sh" "${TARGET_PLATFORM}")
    PACKAGE_VERSION="${TARGET_PLATFORM}-v${VERSION}"
fi

REGISTRY_URL="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages?package_name=pimeleon&package_version=${PACKAGE_VERSION}"

echo "[INFO] Querying GitLab Generic Package Registry for: pimeleon/${PACKAGE_VERSION}"
echo "[DEBUG] URL: ${REGISTRY_URL}"

HTTP_RESPONSE=$(curl -sk -w "\n%{http_code}" --header "JOB-TOKEN: $CI_JOB_TOKEN" "${REGISTRY_URL}")
STATUS=$(echo "$HTTP_RESPONSE" | tail -1)
RESULT=$(echo "$HTTP_RESPONSE" | sed '$d')

if [ "$STATUS" != "200" ]; then
    echo "[ERROR] Registry query failed with HTTP ${STATUS}"
    echo "[DEBUG] Response: ${RESULT}"
    exit 1
fi

# Check if the package list contains an entry with an ID (meaning it exists)
if echo "$RESULT" | grep -q '"id":'; then
    echo "IMAGE_EXISTS=true" >> image.env
    echo "PACKAGE_VERSION=${PACKAGE_VERSION}" >> image.env
    echo "[SUCCESS] OS image version '${PACKAGE_VERSION}' found in registry. Build can be skipped if sources match."
else
    echo "IMAGE_EXISTS=false" >> image.env
    echo "PACKAGE_VERSION=${PACKAGE_VERSION}" >> image.env
    echo "[INFO] OS image version '${PACKAGE_VERSION}' NOT found in registry. Full build required."
fi

#!/bin/sh
set -eu

# Check if the Pimeleon image for this version already exists in the registry

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

echo "Checking registry for pimeleon/${PACKAGE_VERSION}..."
echo "  URL: ${REGISTRY_URL}"

HTTP_RESPONSE=$(curl -sk -w "\n%{http_code}" --header "JOB-TOKEN: $CI_JOB_TOKEN" "${REGISTRY_URL}")
STATUS=$(echo "$HTTP_RESPONSE" | tail -1)
RESULT=$(echo "$HTTP_RESPONSE" | sed '$d')

echo "  HTTP status: ${STATUS}"

if [ "$STATUS" != "200" ]; then
  echo "ERROR: Registry query failed with HTTP ${STATUS}"
  echo "  Response: ${RESULT}"
  exit 1
fi

if echo "$RESULT" | grep -q '"id"'; then
  echo "IMAGE_EXISTS=true" >> image.env
  echo "PACKAGE_VERSION=${PACKAGE_VERSION}" >> image.env
  echo "Image pimeleon/${PACKAGE_VERSION} already exists in registry — build will be skipped"
else
  echo "IMAGE_EXISTS=false" >> image.env
  echo "PACKAGE_VERSION=${PACKAGE_VERSION}" >> image.env
  echo "Image pimeleon/${PACKAGE_VERSION} not found — build required"
fi

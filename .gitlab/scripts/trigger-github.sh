#!/bin/sh
set -eu

# Install dependencies needed for version calculation and API requests
apk add --no-cache curl git >/dev/null 2>&1 || true

# Trigger GitHub Actions workflow on pimeleon/build-pimeleon via repository_dispatch.
#
# Inputs (CI environment):
#   TARGET_PLATFORM, GITHUB_REGISTRY_PUSH_TOKEN (PAT with repo scope)

GITHUB_REPO="pimeleon/build-pimeleon"

if [ -z "${GITHUB_REGISTRY_PUSH_TOKEN:-}" ]; then
    echo "Error: GITHUB_REGISTRY_PUSH_TOKEN not set. Cannot trigger GitHub Actions."
    exit 1
fi

VERSION=$(sh .gitlab/scripts/resolve-version.sh base "${TARGET_PLATFORM}")

echo "Triggering GitHub Actions deploy-r2 on ${GITHUB_REPO}"
echo "  Platform: ${TARGET_PLATFORM}"
echo "  Version:  v${VERSION}"
echo "  Ref:      ${CI_COMMIT_REF_NAME}"

HTTP_CODE=$(curl -s -o /tmp/gh-dispatch-response.txt -w "%{http_code}" \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_REGISTRY_PUSH_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPO}/dispatches" \
    -d "{
        \"event_type\": \"deploy-r2\",
        \"client_payload\": {
            \"platform\": \"${TARGET_PLATFORM}\",
            \"version\": \"${VERSION}\",
            \"tag\": \"v${VERSION}\",
            \"commit_sha\": \"${CI_COMMIT_SHORT_SHA}\",
            \"source_branch\": \"${CI_COMMIT_REF_NAME}\"
        }
    }")

if [ "$HTTP_CODE" = "204" ]; then
    echo "GitHub Actions workflow triggered successfully."
else
    echo "Error: GitHub API returned HTTP ${HTTP_CODE}"
    cat /tmp/gh-dispatch-response.txt
    exit 1
fi

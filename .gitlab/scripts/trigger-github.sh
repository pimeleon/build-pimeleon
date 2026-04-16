#!/bin/sh
set -eu

# Install dependencies needed for version calculation and API requests
apk add --no-cache curl git >/dev/null 2>&1 || true

# Trigger the "Pimeleon Production Build" GitHub Actions workflow via workflow_dispatch.
#
# Inputs (CI environment):
#   TARGET_PLATFORM, PIMELEON_VERSION, CI_COMMIT_REF_NAME
#   GITHUB_REGISTRY_PUSH_TOKEN (PAT with repo scope)

GITHUB_REPO="pimeleon/build-pimeleon"
WORKFLOW_FILE="build.yml"

if [ -z "${GITHUB_REGISTRY_PUSH_TOKEN:-}" ]; then
    echo "Error: GITHUB_REGISTRY_PUSH_TOKEN not set. Cannot trigger GitHub Actions."
    exit 1
fi

echo "Triggering 'Pimeleon Production Build' on ${GITHUB_REPO}"
echo "  Platform: ${TARGET_PLATFORM}"
echo "  Version:  ${PIMELEON_VERSION:-unset}"
echo "  Ref:      ${CI_COMMIT_REF_NAME}"

[ -n "${PIMELEON_VERSION:-}" ] || {
    echo "Error: PIMELEON_VERSION not set. Cannot trigger GitHub Actions consistently."
    exit 1
}

HTTP_CODE=$(curl -s -o /tmp/gh-dispatch-response.txt -w "%{http_code}" \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_REGISTRY_PUSH_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPO}/actions/workflows/${WORKFLOW_FILE}/dispatches" \
    -d "{
        \"ref\": \"${CI_COMMIT_REF_NAME}\",
        \"inputs\": {
            \"target_platform\": \"${TARGET_PLATFORM}\",
            \"version\": \"${PIMELEON_VERSION}\",
            \"force_rebuild\": \"false\"
        }
    }")

if [ "$HTTP_CODE" = "204" ]; then
    echo "GitHub Actions workflow triggered successfully."
else
    echo "Error: GitHub API returned HTTP ${HTTP_CODE}"
    cat /tmp/gh-dispatch-response.txt
    exit 1
fi

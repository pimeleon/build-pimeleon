#!/bin/sh
set -eu

# Install dependencies needed for version calculation and API requests
apk add --no-cache curl git >/dev/null 2>&1 || true

# Trigger the "Pimeleon Production Build" GitHub Actions workflow via workflow_dispatch.
# GitHub Actions resolves the version independently via get-next-version.sh + GHCR.
#
# Inputs (CI environment):
#   TARGET_PLATFORM, CI_COMMIT_REF_NAME
#   PIMELEON_VERSION             — validated to confirm setup:platform ran
#   GITHUB_REGISTRY_PUSH_TOKEN   — PAT with repo scope

GITHUB_REPO="pimeleon/build-pimeleon"
WORKFLOW_FILE="build.yml"

if [ -z "${GITHUB_REGISTRY_PUSH_TOKEN:-}" ]; then
    echo "Error: GITHUB_REGISTRY_PUSH_TOKEN not set. Cannot trigger GitHub Actions."
    exit 1
fi

[ -n "${PIMELEON_VERSION:-}" ] || {
    echo "Error: PIMELEON_VERSION not set — setup:platform artifact missing."
    exit 1
}

echo "Triggering 'Pimeleon Production Build' on ${GITHUB_REPO}"
echo "  Platform: ${TARGET_PLATFORM}"
echo "  Ref:      ${CI_COMMIT_REF_NAME}"

HTTP_CODE=$(curl -s -o /tmp/gh-dispatch-response.txt -w "%{http_code}" \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_REGISTRY_PUSH_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPO}/actions/workflows/${WORKFLOW_FILE}/dispatches" \
    -d "{
        \"ref\": \"${CI_COMMIT_REF_NAME}\",
        \"inputs\": {
            \"target_platform\": \"${TARGET_PLATFORM}\",
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

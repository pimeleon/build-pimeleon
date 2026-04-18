#!/bin/sh
set -eu

# Create an annotated git tag via the GitLab API.
#
# Usage: create-tag.sh <tag-name> <tag-message>
#
# Inputs (env):
#   CI_API_V4_URL, CI_PROJECT_ID, CI_COMMIT_SHA  — auto-injected by GitLab CI
#   GITLAB_PUSH_TOKEN                             — PAT with api scope (project CI variable)

TAG_NAME="${1:-}"
TAG_MESSAGE="${2:-Automated tag ${TAG_NAME}}"

[ -n "$TAG_NAME" ]                  || { echo "[ERROR] tag name is required" >&2; exit 1; }
[ -n "${GITLAB_PUSH_TOKEN:-}" ]     || { echo "[ERROR] GITLAB_PUSH_TOKEN is not set" >&2; exit 1; }
[ -n "${CI_API_V4_URL:-}" ]         || { echo "[ERROR] CI_API_V4_URL is not set" >&2; exit 1; }
[ -n "${CI_PROJECT_ID:-}" ]         || { echo "[ERROR] CI_PROJECT_ID is not set" >&2; exit 1; }
[ -n "${CI_COMMIT_SHA:-}" ]         || { echo "[ERROR] CI_COMMIT_SHA is not set" >&2; exit 1; }
command -v curl >/dev/null 2>&1     || { echo "[ERROR] curl is required" >&2; exit 1; }

_api="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/repository/tags"

# Check if tag already exists
_exists=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "PRIVATE-TOKEN: ${GITLAB_PUSH_TOKEN}" \
    "${_api}/${TAG_NAME}")

if [ "${_exists}" = "200" ]; then
    echo "[INFO] Tag ${TAG_NAME} already exists — skipping."
    exit 0
fi

# Create the annotated tag
_raw=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "PRIVATE-TOKEN: ${GITLAB_PUSH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"tag_name\":\"${TAG_NAME}\",\"ref\":\"${CI_COMMIT_SHA}\",\"message\":\"${TAG_MESSAGE}\"}" \
    "${_api}")

_status=$(printf '%s' "$_raw" | tail -1)
_body=$(printf '%s' "$_raw" | sed '$d')

if [ "$_status" = "201" ]; then
    echo "[INFO] Created annotated tag: ${TAG_NAME}"
else
    echo "[ERROR] GitLab API returned HTTP ${_status}" >&2
    echo "[DEBUG] ${_body}" >&2
    exit 1
fi

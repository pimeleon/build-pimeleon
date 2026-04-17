#!/bin/sh
set -eu

# Create an annotated git tag via the GitLab API.
# Uses CI_JOB_TOKEN — no write_repository scope or git push needed.
#
# Usage: create-tag.sh <tag-name> <tag-message>
#
# Inputs (env — all auto-injected by GitLab CI):
#   CI_API_V4_URL, CI_PROJECT_ID, CI_COMMIT_SHA, CI_JOB_TOKEN

TAG_NAME="${1:-}"
TAG_MESSAGE="${2:-Automated tag ${TAG_NAME}}"

[ -n "$TAG_NAME" ]              || { echo "[ERROR] tag name is required" >&2; exit 1; }
[ -n "${CI_JOB_TOKEN:-}" ]      || { echo "[ERROR] CI_JOB_TOKEN is not set" >&2; exit 1; }
[ -n "${CI_API_V4_URL:-}" ]     || { echo "[ERROR] CI_API_V4_URL is not set" >&2; exit 1; }
[ -n "${CI_PROJECT_ID:-}" ]     || { echo "[ERROR] CI_PROJECT_ID is not set" >&2; exit 1; }
[ -n "${CI_COMMIT_SHA:-}" ]     || { echo "[ERROR] CI_COMMIT_SHA is not set" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "[ERROR] curl is required" >&2; exit 1; }

_api="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/repository/tags"

# Check if tag already exists
_exists=$(curl -sf -o /dev/null -w "%{http_code}" \
    -H "JOB-TOKEN: ${CI_JOB_TOKEN}" \
    "${_api}/${TAG_NAME}" 2>/dev/null) || true

if [ "${_exists}" = "200" ]; then
    echo "[INFO] Tag ${TAG_NAME} already exists — skipping."
    exit 0
fi

_resp=$(curl -sf -w "\n%{http_code}" \
    -X POST \
    -H "JOB-TOKEN: ${CI_JOB_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"tag_name\":\"${TAG_NAME}\",\"ref\":\"${CI_COMMIT_SHA}\",\"message\":\"${TAG_MESSAGE}\"}" \
    "${_api}" 2>/dev/null)

_status=$(printf '%s' "$_resp" | tail -1)
_body=$(printf '%s' "$_resp" | sed '$d')

if [ "$_status" = "201" ]; then
    echo "[INFO] Created annotated tag: ${TAG_NAME}"
else
    echo "[ERROR] GitLab API POST /tags returned HTTP ${_status}" >&2
    echo "[DEBUG] ${_body}" >&2
    exit 1
fi

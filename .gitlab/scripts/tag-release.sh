#!/bin/sh
set -eu

# Poll GitHub Releases until the expected version is published, then create
# an annotated release tag on GitLab: release-{platform}-v{version}
#
# Inputs (env):
#   TARGET_PLATFORM          — e.g. rpi3-bookworm
#   PIMELEON_VERSION         — e.g. 0.4.2  (the version just built and triggered)
#   PIMELEON_APPS_GITHUB_TOKEN / GITHUB_TOKEN — for GitHub API reads
#   GITLAB_PUSH_TOKEN / CI_JOB_TOKEN          — for git push
#
# Tuning:
#   TAG_RELEASE_TIMEOUT   — max seconds to wait for GitHub release (default: 600)
#   TAG_RELEASE_INTERVAL  — poll interval in seconds (default: 30)

PLATFORM="${TARGET_PLATFORM:-}"
EXPECTED_VERSION="${PIMELEON_VERSION:-}"
GITHUB_REPO="${GITHUB_REPO:-pimeleon/build-pimeleon}"

[ -n "$PLATFORM" ]          || { echo "[ERROR] TARGET_PLATFORM is not set" >&2;  exit 1; }
[ -n "$EXPECTED_VERSION" ]  || { echo "[ERROR] PIMELEON_VERSION is not set" >&2; exit 1; }

_token="${PIMELEON_APPS_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}"
[ -n "$_token" ] || { echo "[ERROR] No GitHub token available (PIMELEON_APPS_GITHUB_TOKEN)" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || { echo "[ERROR] curl is required" >&2; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "[ERROR] jq is required"   >&2; exit 1; }

_org=$(printf '%s' "$GITHUB_REPO" | cut -d/ -f1)
_repo=$(printf '%s' "$GITHUB_REPO" | cut -d/ -f2)
_expected_tag="${PLATFORM}-v${EXPECTED_VERSION}"

MAX_WAIT="${TAG_RELEASE_TIMEOUT:-600}"
INTERVAL="${TAG_RELEASE_INTERVAL:-30}"

echo "[INFO] Waiting for GitHub release '${_expected_tag}' (timeout: ${MAX_WAIT}s)..."

elapsed=0
while [ "$elapsed" -lt "$MAX_WAIT" ]; do
    _resp=$(curl -sf \
        -H "Authorization: Bearer ${_token}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${_org}/${_repo}/releases?per_page=50" 2>/dev/null) || true

    _found=$(printf '%s' "${_resp:-[]}" | jq -r --arg t "${_expected_tag}" \
        '[.[] | .tag_name | select(. == $t)] | first // empty' 2>/dev/null) || true

    if [ -n "${_found}" ]; then
        echo "[INFO] Confirmed: GitHub release '${_found}' is published."
        break
    fi

    echo "[INFO] Not yet available. Retrying in ${INTERVAL}s... (${elapsed}/${MAX_WAIT}s elapsed)"
    sleep "$INTERVAL"
    elapsed=$((elapsed + INTERVAL))
done

if [ "$elapsed" -ge "$MAX_WAIT" ]; then
    echo "[ERROR] Timed out after ${MAX_WAIT}s waiting for GitHub release '${_expected_tag}'" >&2
    exit 1
fi

RELEASE_TAG="release-${PLATFORM}-v${EXPECTED_VERSION}"
SCRIPT_DIR="$(dirname "$0")"
chmod +x "${SCRIPT_DIR}/create-tag.sh"
sh "${SCRIPT_DIR}/create-tag.sh" "${RELEASE_TAG}" "Release ${PLATFORM} v${EXPECTED_VERSION}"

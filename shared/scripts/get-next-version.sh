#!/bin/sh
set -eu

# Compute the next semantic version for a Pimeleon platform build.
#
# Registry selection (mutually exclusive):
#   GITHUB_ACTIONS=true  → GHCR container image tags (GitHub Actions only)
#   otherwise            → GitLab Package Registry (CI_JOB_TOKEN or GITLAB_FETCH_TOKEN)
# If the registry is unreachable or has no matching version, the build fails — no fallback.
#
# NOTE: This script is intentionally self-contained (no lib-api.sh dependency)
# because it is sometimes *sourced* by build.sh inside the builder container,
# where $(dirname "$0") resolves to the shell binary path, not the script dir.

GITHUB_REPO="${GITHUB_REPO:-pimeleon/build-pimeleon}"

die() { echo "[ERROR] get-next-version: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# GitLab API GET — PRIVATE-TOKEN (local/external) or JOB-TOKEN (CI runner)
# ---------------------------------------------------------------------------
_gitlab_api_get() {
    _request_url="$1"
    command -v curl >/dev/null 2>&1 || return 1

    if [ -n "${GITLAB_FETCH_TOKEN:-}" ]; then
        curl -skf -H "PRIVATE-TOKEN: ${GITLAB_FETCH_TOKEN}" \
            "$_request_url" 2>/dev/null || return 1
    elif [ -n "${CI_JOB_TOKEN:-}" ]; then
        curl -skf -H "JOB-TOKEN: ${CI_JOB_TOKEN}" \
            "$_request_url" 2>/dev/null || return 1
    else
        return 1
    fi
}

# ---------------------------------------------------------------------------
# GitLab Package Registry — latest package version matching {platform}-v*
# ---------------------------------------------------------------------------
_gitlab_latest_package_version() {
    _platform="$1"
    _url="${CI_API_V4_URL:-${GITLAB_API_V4_URL:-https://gitlab.pirouter.dev/api/v4}}"
    _project="${CI_PROJECT_ID:-${GITLAB_PROJECT_ID:-13}}"
    _api_path="/projects/${_project}/packages?package_name=pimeleon&order_by=created_at&sort=desc&per_page=50"
    command -v curl >/dev/null 2>&1 || die "curl is required"
    command -v jq   >/dev/null 2>&1 || die "jq is required"

    _resp=$(_gitlab_api_get "${_url}${_api_path}") || die "GitLab registry query failed for ${_platform}"

    _version=$(printf '%s' "$_resp" | jq -r --arg p "${_platform}-v" \
        '[.[] | select(.version | startswith($p)) | .version] | first // empty' 2>/dev/null) || \
        die "failed to parse GitLab registry response for ${_platform}"
    if [ -z "$_version" ] || [ "$_version" = "null" ]; then
        die "no published version found for ${_platform} in GitLab registry"
    fi
    printf '%s' "$_version" | sed "s/^${_platform}-v//"
}


# ---------------------------------------------------------------------------
# GHCR — latest builder image tag matching {platform}-v*
# ---------------------------------------------------------------------------
_github_api_get() {
    _request_url="$1"
    _token="${PIMELEON_APPS_GITHUB_TOKEN:-${GITHUB_REGISTRY_PUSH_TOKEN:-${GITHUB_TOKEN:-}}}"
    [ -n "$_token" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1

    curl -sf \
        -H "Authorization: Bearer ${_token}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$_request_url" 2>/dev/null || return 1
}

_github_latest_version() {
    _platform="$1"
    _org=$(printf '%s' "$GITHUB_REPO" | cut -d/ -f1)
    _repo=$(printf '%s' "$GITHUB_REPO" | cut -d/ -f2)
    command -v curl >/dev/null 2>&1 || die "curl is required"
    command -v jq   >/dev/null 2>&1 || die "jq is required"

    _resp=$(_github_api_get \
        "https://api.github.com/repos/${_org}/${_repo}/releases?per_page=50") || \
        die "GitHub Releases query failed for ${_platform}"

    _tag=$(printf '%s' "$_resp" | jq -r --arg p "${_platform}-v" \
        '[.[] | .tag_name | select(startswith($p))] | first // empty' \
        2>/dev/null) || die "failed to parse GitHub Releases response for ${_platform}"
    if [ -z "$_tag" ] || [ "$_tag" = "null" ]; then
        die "no published release found for ${_platform} in GitHub"
    fi
    printf '%s' "$_tag" | sed "s/^${_platform}-v//"
}


# ---------------------------------------------------------------------------
# Shared semver bump
# ---------------------------------------------------------------------------
_bump_patch() {
    _ver="$1"
    _major=$(printf '%s' "$_ver" | cut -d. -f1)
    _minor=$(printf '%s' "$_ver" | cut -d. -f2)
    _patch=$(printf '%s' "$_ver" | cut -d. -f3)
    echo "${_major}.${_minor}.$((_patch + 1))"
}

get_next_version() {
    platform="${1:-}"
    [ -n "$platform" ] || die "platform argument is required"

    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
        _bump_patch "$(_github_latest_version "$platform")"
    else
        _bump_patch "$(_gitlab_latest_package_version "$platform")"
    fi
}

case "$0" in
    *get-next-version.sh) get_next_version "$@" ;;
esac

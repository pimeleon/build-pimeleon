#!/bin/sh
set -eu

# Compute the next semantic version for a Pimeleon platform build.
#
# Version source: GitLab Package Registry only (GITLAB_FETCH_TOKEN | CI_JOB_TOKEN).
# If no published version is found, the build fails — no fallback.
#
# NOTE: This script is intentionally self-contained (no lib-api.sh dependency)
# because it is sometimes *sourced* by build.sh inside the builder container,
# where $(dirname "$0") resolves to the shell binary path, not the script dir.

die() { echo "[ERROR] get-next-version: $*" >&2; exit 1; }

_gitlab_api_get() {
    _request_url="$1"
    command -v curl >/dev/null 2>&1 || return 1

    if [ -n "${GITLAB_FETCH_TOKEN:-}" ]; then
        curl -sk -H "PRIVATE-TOKEN: ${GITLAB_FETCH_TOKEN}" \
            "$_request_url" 2>/dev/null || return 1
    elif [ -n "${CI_JOB_TOKEN:-}" ]; then
        curl -sk -H "JOB-TOKEN: ${CI_JOB_TOKEN}" \
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


_gitlab_version_exists() {
    _platform="$1"
    _version="$2"
    _url="${CI_API_V4_URL:-${GITLAB_API_V4_URL:-https://gitlab.pirouter.dev/api/v4}}"
    _project="${CI_PROJECT_ID:-${GITLAB_PROJECT_ID:-}}"
    command -v curl >/dev/null 2>&1 || return 1
    command -v jq   >/dev/null 2>&1 || return 1

    _resp=$(_gitlab_api_get \
        "${_url}/projects/${_project}/packages?package_name=pimeleon&package_version=${_platform}-v${_version}") || return 1

    _count=$(printf '%s' "$_resp" | jq 'length' 2>/dev/null) || return 1
    [ "${_count:-0}" -gt 0 ]
}

_bump_from_flags() {
    _base_version="$1"
    _major_n="$2"
    _minor_n="$3"
    _patch_n="$4"

    _major=$(printf '%s' "$_base_version" | cut -d. -f1)
    _minor=$(printf '%s' "$_base_version" | cut -d. -f2)
    _patch=$(printf '%s' "$_base_version" | cut -d. -f3)

    if [ "$_major_n" -gt 0 ]; then
        _min=0; [ "$_minor_n" -gt 0 ] && _min=1
        _pat=0; [ "$_patch_n" -gt 0 ] && _pat=1
        echo "$((_major + 1)).${_min}.${_pat}"
    elif [ "$_minor_n" -gt 0 ]; then
        _pat=0; [ "$_patch_n" -gt 0 ] && _pat=1
        echo "${_major}.$((_minor + 1)).${_pat}"
    elif [ "$_patch_n" -gt 0 ]; then
        echo "${_major}.${_minor}.$((_patch + 1))"
    else
        echo "${_base_version}"
    fi
}

get_next_version() {
    platform="${1:-}"
    [ -n "$platform" ] || die "platform argument is required"

    base_version=$(_gitlab_latest_package_version "$platform")

    # Bump patch by 1 from the latest published version
    candidate_version=$(_bump_from_flags "$base_version" 0 0 1)

    # Skip any versions already published in the registry
    while _gitlab_version_exists "$platform" "$candidate_version"; do
        candidate_version=$(_bump_from_flags "$candidate_version" 0 0 1)
    done

    echo "$candidate_version"
}

case "$0" in
    *get-next-version.sh) get_next_version "$@" ;;
esac

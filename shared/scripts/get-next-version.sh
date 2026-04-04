#!/bin/sh
set -eu

GITHUB_REPO="${GITHUB_REPO:-pimeleon/build-pimeleon}"
DEFAULT_BASE_VERSION="0.3.0"

_github_latest_version() {
    _platform="$1"
    _token="${GITHUB_REGISTRY_PUSH_TOKEN:-${GITHUB_TOKEN:-}}"
    command -v curl >/dev/null 2>&1 || return 1
    if [ -n "$_token" ]; then
        _resp=$(curl -sf -H "Authorization: Bearer ${_token}" -H "Accept: application/vnd.github+json" "https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=50" 2>/dev/null) || return 1
    else
        _resp=$(curl -sf -H "Accept: application/vnd.github+json" "https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=50" 2>/dev/null) || return 1
    fi
    _tag=$(printf '%s' "$_resp" | grep '"tag_name"' | grep "\"${_platform}-v" | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/') || return 1
    [ -n "$_tag" ] || return 1
    printf '%s' "$_tag" | sed "s/^${_platform}-v//"
}

_gitlab_latest_version() {
    _platform="$1"
    _url="${CI_API_V4_URL:-https://gitlab.pirouter.dev/api/v4}"
    _project_id="${CI_PROJECT_ID:-13}"
    _token="${GITLAB_FETCH_TOKEN:-${CI_JOB_TOKEN:-${PIMELEON_APPS_READ_TOKEN:-}}}"
    [ -n "$_token" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1
    _resp=$(curl -sk -H "JOB-TOKEN: ${_token}" -H "PRIVATE-TOKEN: ${_token}" "${_url}/projects/${_project_id}/packages?package_name=pimeleon&order_by=created_at&sort=desc&per_page=50" 2>/dev/null)
    _version=$(printf '%s' "$_resp" | jq -r '[.[] | select(.version | startswith("'$_platform'-v")) | .version] | first' 2>/dev/null) || return 1
    [ -n "$_version" ] && [ "$_version" != "null" ] || return 1
    printf '%s' "$_version" | sed "s/^${_platform}-v//"
}

_baseline_ref() {
    _platform="$1"
    _version="$2"
    # Try finding the tag locally; if it fails, fallback to the first commit
    git rev-list -1 "${_platform}-v${_version}" 2>/dev/null || git rev-list --max-parents=0 HEAD
}

_count() {
    _text="$1"
    _pat="$2"
    [ -n "$_text" ] || { echo 0; return; }
    printf '%s\n' "$_text" | grep -cE "$_pat" || true
}

get_next_version() {
    platform="${1:-}"
    [ -n "$platform" ] || { echo "Error: platform is required" >&2; exit 1; }
    base_version=$(_gitlab_latest_version "$platform" 2>/dev/null || echo "")
    if [ -z "$base_version" ]; then
        base_version=$(_github_latest_version "$platform" 2>/dev/null) || base_version=""
    fi
    if [ -z "$base_version" ]; then
        base_version=$(git tag -l "${platform}-v*" --sort=-v:refname 2>/dev/null | head -1 | sed "s/^${platform}-v//") || base_version=""
    fi
    [ -n "$base_version" ] || base_version="$DEFAULT_BASE_VERSION"

    # NEW: If we don't have a tag for the resolved base_version, find the last commit
    # that matches the version's hash if available in registry, OR fallback to current behavior.
    last_ref=$(_baseline_ref "$platform" "$base_version")

    major=$(printf '%s' "$base_version" | cut -d. -f1)
    minor=$(printf '%s' "$base_version" | cut -d. -f2)
    patch=$(printf '%s' "$base_version" | cut -d. -f3)
    msgs=$(git log "${last_ref}..HEAD" --format="%s" -- "containers/" "shared/containers/" "shared/ansible/" "shared/configs/" "shared/scripts/" "docker-compose.yml" "requirements.txt" "apps/" 2>/dev/null) || msgs=""
    major_n=$(_count "$msgs" "^(feat|fix|refactor)(\([^)]*\))?!:")
    minor_n=$(_count "$msgs" "^(feat|refactor)(\([^)]*\))?:")
    service_n=$(_count "$msgs" "^(docs|chore|ci|style|test)(\([^)]*\))?!?:")
    total_n=$(_count "$msgs" ".")
    patch_n=$((total_n - major_n - minor_n - service_n))
    [ "$patch_n" -ge 0 ] || patch_n=0

    if [ "$major_n" -gt 0 ]; then
        _min=0; [ "$minor_n" -gt 0 ] && _min=1
        _pat=0; [ "$patch_n" -gt 0 ] && _pat=1
        echo "$((major + 1)).${_min}.${_pat}"
    elif [ "$minor_n" -gt 0 ]; then
        _pat=0; [ "$patch_n" -gt 0 ] && _pat=1; echo "${major}.$((minor + 1)).${_pat}"
    elif [ "$patch_n" -gt 0 ]; then
        echo "${major}.${minor}.$((patch + 1))"
    else
        echo "${base_version}"
    fi
}
case "$0" in
    *get-next-version.sh) get_next_version "$@" ;;
esac

#!/bin/sh
set -eu

# Compute the next semantic version for a Pimeleon platform build.
#
# Version source priority (highest → lowest):
#   1. GitHub Releases (GITHUB_REGISTRY_PUSH_TOKEN)
#   2. GitLab Package Registry (GITLAB_FETCH_TOKEN)
#   3. Local git tags (git tag -l)
#   4. Hardcoded default (0.3.0)
#
# NOTE: This script is intentionally self-contained (no lib-api.sh dependency)
# because it is sometimes *sourced* by build.sh inside the builder container,
# where $(dirname "$0") resolves to the shell binary path, not the script dir.

GITHUB_REPO="${GITHUB_REPO:-pimeleon/build-pimeleon}"
DEFAULT_BASE_VERSION="0.1.0"

die() { echo "[ERROR] get-next-version: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# GitHub Container Registry (GHCR) — latest builder image tag matching
# {platform}-v* in /orgs/{org}/packages/container/{repo}%2Fbuilder/versions
# ---------------------------------------------------------------------------
_github_latest_version() {
    _platform="$1"
    _token="${PIMELEON_APPS_GITHUB_TOKEN:-${GITHUB_REGISTRY_PUSH_TOKEN:-${GITHUB_TOKEN:-}}}"
    [ -n "$_token" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1
    command -v jq   >/dev/null 2>&1 || return 1

    # Derive org and URL-encoded package name from GITHUB_REPO
    # e.g. pimeleon/build-pimeleon → org=pimeleon, pkg=build-pimeleon%2Fbuilder
    _org=$(printf '%s' "$GITHUB_REPO" | cut -d/ -f1)
    _repo=$(printf '%s' "$GITHUB_REPO" | cut -d/ -f2)
    _pkg="${_repo}%2Fbuilder"

    _resp=$(curl -sf \
        -H "Authorization: Bearer ${_token}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/orgs/${_org}/packages/container/${_pkg}/versions?per_page=50" \
        2>/dev/null) || return 1

    _tag=$(printf '%s' "$_resp" | jq -r --arg p "${_platform}-v" \
        '[.[] | .metadata.container.tags[] | select(startswith($p))] | first // empty' \
        2>/dev/null) || return 1
    [ -n "$_tag" ] || return 1
    printf '%s' "$_tag" | sed "s/^${_platform}-v//"
}

# ---------------------------------------------------------------------------
# GitLab Package Registry — latest package version matching {platform}-v*
# Sends exactly one auth header — never both JOB-TOKEN and PRIVATE-TOKEN.
# ---------------------------------------------------------------------------
_gitlab_latest_package_version() {
    _platform="$1"
    _url="${CI_API_V4_URL:-${GITLAB_API_V4_URL:-https://gitlab.pirouter.dev/api/v4}}"
    _project="${CI_PROJECT_ID:-${GITLAB_PROJECT_ID:-13}}"
    _api_path="/projects/${_project}/packages?package_name=pimeleon&order_by=created_at&sort=desc&per_page=50"
    command -v curl >/dev/null 2>&1 || return 1
    command -v jq   >/dev/null 2>&1 || return 1

    if [ -n "${GITLAB_FETCH_TOKEN:-}" ]; then
        _resp=$(curl -sk -H "PRIVATE-TOKEN: ${GITLAB_FETCH_TOKEN}" \
            "${_url}${_api_path}" 2>/dev/null) || return 1
    else
        return 1
    fi

    _version=$(printf '%s' "$_resp" | jq -r --arg p "${_platform}-v" \
        '[.[] | select(.version | startswith($p)) | .version] | first // empty' 2>/dev/null) || return 1
    [ -n "$_version" ] && [ "$_version" != "null" ] || return 1
    printf '%s' "$_version" | sed "s/^${_platform}-v//"
}

# ---------------------------------------------------------------------------
# Resolve the git ref for the baseline version.
# Falls back to first commit instead of dying so that new platforms can bootstrap.
# ---------------------------------------------------------------------------
_baseline_ref() {
    _platform="$1"
    _version="$2"

    # 1. Exact version tag
    _ref=$(git rev-list -1 "${_platform}-v${_version}" 2>/dev/null) && {
        printf '%s' "$_ref"; return
    }
    # 2. Any platform tag (most recent by semver)
    _any_tag=$(git tag -l "${_platform}-v*" --sort=-v:refname 2>/dev/null | head -1)
    if [ -n "$_any_tag" ]; then
        _ref=$(git rev-list -1 "$_any_tag" 2>/dev/null) && {
            printf '%s' "$_ref"; return
        }
    fi
    # 3. Fallback to first commit
    git rev-list --max-parents=0 HEAD 2>/dev/null || die "failed to resolve git baseline"
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

    # Resolve base version: GitHub → GitLab → local git tags → default
    base_version=$(_github_latest_version "$platform" 2>/dev/null) || base_version=""
    [ -n "$base_version" ] || base_version=$(_gitlab_latest_package_version "$platform" 2>/dev/null) || base_version=""
    if [ -z "$base_version" ]; then
        base_version=$(git tag -l "${platform}-v*" --sort=-v:refname 2>/dev/null | head -1 | \
            sed "s/^${platform}-v//") || base_version=""
    fi
    [ -n "$base_version" ] || base_version="$DEFAULT_BASE_VERSION"

    last_ref=$(_baseline_ref "$platform" "$base_version")

    major=$(printf '%s' "$base_version" | cut -d. -f1)
    minor=$(printf '%s' "$base_version" | cut -d. -f2)
    patch=$(printf '%s' "$base_version" | cut -d. -f3)

    msgs=$(git log "${last_ref}..HEAD" --format="%s" -- \
        "shared/containers/" "shared/ansible/" "shared/configs/" "shared/scripts/" \
        "docker-compose.yml" "requirements.txt" 2>/dev/null) || msgs=""


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
        _pat=0; [ "$patch_n" -gt 0 ] && _pat=1
        echo "${major}.$((minor + 1)).${_pat}"
    elif [ "$patch_n" -gt 0 ]; then
        echo "${major}.${minor}.$((patch + 1))"
    else
        echo "${base_version}"
    fi
}

case "$0" in
    *get-next-version.sh) get_next_version "$@" ;;
esac

#!/bin/sh
# Resolve the next semver version for a platform.
#
# Base version source priority:
#   1. Latest GitHub Release tag matching {platform}-v*
#   2. Latest local git tag matching {platform}-v*
#   3. Hardcoded default (0.3.0)
#
# Bump rules (applied to commits on tracked build paths since last release):
#   Breaking (feat!:/fix!:) → (major+1).(1 if minor commits else 0).(1 if patch commits else 0)
#   Minor    (feat:/refactor:)  → major.(minor+1).(1 if patch commits else 0)
#   Patch    (everything else except service commits) → major.minor.(patch+1)
#   Service  (docs:/chore:/ci:/style:/test:) → no bump
#
# Usage: get-next-version.sh <platform>
#
# Env (optional):
#   GITHUB_REPO                — owner/repo (default: pimeleon/build-pimeleon)
#   GITHUB_REGISTRY_PUSH_TOKEN / GITHUB_TOKEN — PAT for private repo access

set -eu

GITHUB_REPO="${GITHUB_REPO:-pimeleon/build-pimeleon}"
DEFAULT_BASE_VERSION="0.3.0"

# Fetch the latest release version for a platform from GitHub Releases API.
# Outputs the version string (e.g. "0.3.0") or returns 1 on failure.
_github_latest_version() {
    _platform="$1"
    _token="${GITHUB_REGISTRY_PUSH_TOKEN:-${GITHUB_TOKEN:-}}"

    command -v curl >/dev/null 2>&1 || return 1

    if [ -n "$_token" ]; then
        _resp=$(curl -sf \
            -H "Authorization: Bearer ${_token}" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=50" 2>/dev/null) || return 1
    else
        _resp=$(curl -sf \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=50" 2>/dev/null) || return 1
    fi

    _tag=$(printf '%s' "$_resp" \
        | grep '"tag_name"' \
        | grep "\"${_platform}-v" \
        | head -1 \
        | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/') || return 1

    [ -n "$_tag" ] || return 1
    printf '%s' "$_tag" | sed "s/^${_platform}-v//"
}

# Return the git commit ref for the release tag, or the first repo commit if no tag exists.
_baseline_ref() {
    _platform="$1"
    _version="$2"
    git rev-list -1 "${_platform}-v${_version}" 2>/dev/null \
        || git rev-list --max-parents=0 HEAD
}

# Count lines in $1 matching ERE pattern $2. Safe when input is empty.
_count() {
    _text="$1"
    _pat="$2"
    [ -n "$_text" ] || { echo 0; return; }
    printf '%s\n' "$_text" | grep -cE "$_pat" || true
}

get_next_version() {
    platform="${1:-}"
    [ -n "$platform" ] || { echo "Error: platform is required" >&2; exit 1; }

    # --- Resolve base version ---
    base_version=$(_github_latest_version "$platform" 2>/dev/null) || base_version=""

    if [ -z "$base_version" ]; then
        base_version=$(git tag -l "${platform}-v*" --sort=-v:refname 2>/dev/null \
            | head -1 \
            | sed "s/^${platform}-v//") || base_version=""
    fi

    [ -n "$base_version" ] || base_version="$DEFAULT_BASE_VERSION"

    last_ref=$(_baseline_ref "$platform" "$base_version")

    major=$(printf '%s' "$base_version" | cut -d. -f1)
    minor=$(printf '%s' "$base_version" | cut -d. -f2)
    patch=$(printf '%s' "$base_version" | cut -d. -f3)

    # --- Collect commit subjects on tracked build paths since last release ---
    msgs=$(git log "${last_ref}..HEAD" --format="%s" -- \
        "apps/${platform}/" \
        "containers/" \
        "shared/containers/" \
        "shared/ansible/" \
        "shared/configs/" \
        "shared/scripts/" \
        "docker-compose.yml" \
        "requirements.txt" \
        2>/dev/null) || msgs=""

    # Breaking changes: feat!: / fix!:
    major_n=$(_count "$msgs" "^(feat|fix)(\([^)]*\))?!:")

    # Non-breaking features: feat: / refactor:  (! absent — regex requires : immediately after scope)
    minor_n=$(_count "$msgs" "^(feat|refactor)(\([^)]*\))?:")

    # Service commits: no bump
    service_n=$(_count "$msgs" "^(docs|chore|ci|style|test)(\([^)]*\))?!?:")

    # Total non-empty lines
    total_n=$(_count "$msgs" ".")

    # Patch = everything not major, minor, or service (fix:/build:/perf:/untagged/merges)
    patch_n=$((total_n - major_n - minor_n - service_n))
    [ "$patch_n" -ge 0 ] || patch_n=0

    # --- Apply bump rules ---
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

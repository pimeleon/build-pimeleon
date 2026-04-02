#!/bin/sh
# Resolve the current version for a specific platform with Auto-Bump logic
# Usage: get-next-version.sh [platform]
#
# POSIX sh compatible

set -eu

get_next_version() {
    platform="${1:-}"
    version_file="apps/${platform}/VERSION"
    base_version=""

    # 1. Resolve base version from VERSION file
    if [ -f "$version_file" ]; then
        base_version=$(tr -d '[:space:]' < "$version_file")
    else
        # Fallback to latest tag if file missing
        current_tag=$(git tag -l "${platform}-v*" "v*-${platform}" --sort=-v:refname 2>/dev/null | head -1 || echo "")
        if [ -n "$current_tag" ]; then
            base_version=$(echo "$current_tag" | sed "s/^${platform}-v//; s/^v//; s/-${platform}\$//")
        else
            base_version="0.1.0"
        fi
    fi

    # 2. Skip or Bump logic
    # Minor bump: feat: or refactor: commits touching build paths (including docker-compose.yml)
    # Patch bump: fix:/build:/perf: or untagged commits touching build paths
    # No bump:   docs:/chore:/ci:/style:/test: commits (service commits, never trigger rebuild)

    # Find the commit where the version was last set
    last_version_commit=$(git log -1 --format=%H -- "$version_file" 2>/dev/null || git rev-list --max-parents=0 HEAD)

    major=$(echo "$base_version" | cut -d. -f1)
    minor=$(echo "$base_version" | cut -d. -f2)
    patch=$(echo "$base_version" | cut -d. -f3)

    # Count minor-bump commits: feat: or refactor: touching build paths
    minor_commits=$(git log "$last_version_commit"..HEAD \
            --format="%s" \
            -- \
            "apps/${platform}/" \
            "containers/" \
            "shared/containers/" \
            "shared/ansible/" \
            "shared/configs/" \
            "shared/scripts/" \
            "docker-compose.yml" \
            "requirements.txt" \
            2>/dev/null \
        | grep -cE "^(feat|refactor)(\([^)]*\))?!?:" || true)

    # Count patch-bump commits: anything not service and not minor touching build paths
    patch_commits=$(git log "$last_version_commit"..HEAD \
            --format="%s" \
            -- \
            "apps/${platform}/" \
            "containers/" \
            "shared/containers/" \
            "shared/ansible/" \
            "shared/configs/" \
            "shared/scripts/" \
            "docker-compose.yml" \
            "requirements.txt" \
            2>/dev/null \
        | grep -cvE "^(docs|chore|ci|style|test|feat|refactor)(\([^)]*\))?!?:" || true)

    if [ "${minor_commits}" -gt 0 ]; then
        # Feature or refactor -> MINOR bump, reset patch
        echo "${major}.$((minor + 1)).0"
    elif [ "${patch_commits}" -gt 0 ]; then
        # Fix/build/perf or untagged -> PATCH bump
        echo "${major}.${minor}.$((patch + 1))"
    else
        # Service commits only -> Return stable version for SKIP
        echo "${base_version}"
    fi
}

case "$0" in
    *get-next-version.sh) get_next_version "$@" ;;
esac

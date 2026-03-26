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
    # We check if core dependencies have changed since the last tag or VERSION file update.
    # Dependencies: apps/, shared/ansible/, shared/configs/, shared/scripts/, docker-compose.yml

    # Find the commit where the version was last set
    last_version_commit=$(git log -1 --format=%H -- "$version_file" 2>/dev/null || git rev-list --max-parents=0 HEAD)

    # Check for changes in core dependencies since that commit
    # If changes exist, we BUMP the patch version.
    if git diff --quiet "$last_version_commit"..HEAD -- \
        "apps/${platform}/" \
        "shared/ansible/" \
        "shared/configs/" \
        "shared/scripts/" \
        "docker-compose.yml" \
        "requirements.txt"; then
        # No changes in dependencies -> Return stable version for SKIP
        echo "${base_version}"
    else
        # Changes detected -> BUMP patch version for NEW BUILD
        major=$(echo "$base_version" | cut -d. -f1)
        minor=$(echo "$base_version" | cut -d. -f2)
        patch=$(echo "$base_version" | cut -d. -f3)
        echo "${major}.${minor}.$((patch + 1))"
    fi
}

case "$0" in
    *get-next-version.sh) get_next_version "$@" ;;
esac

#!/bin/sh
# Resolve the current version for a specific platform with Auto-Bump logic
# Usage: get-next-version.sh [platform]
#
# POSIX sh compatible - works in Alpine/BusyBox environments

set -eu

get_next_version() {
    platform="${1:-}"
    current_tag=""

    # Find latest tag for this platform (or any tag if no platform)
    if [ -n "$platform" ]; then
        current_tag=$(git tag -l "*-${platform}" --sort=-v:refname 2>/dev/null | head -1) || current_tag=""
    fi
    # Legacy fallback: v{version}-{platform} or plain v{version}
    if [ -z "$current_tag" ] && [ -n "$platform" ]; then
        current_tag=$(git tag -l "*-${platform}" --sort=-v:refname 2>/dev/null | head -1) || current_tag=""
    fi
    if [ -z "$current_tag" ]; then
        current_tag=$(git describe --tags --abbrev=0 2>/dev/null) || current_tag=""
    fi

    if [ -z "$current_tag" ]; then
        echo "0.1.0"
        return
    fi

    # Strip v prefix and platform suffix for parsing
    base_version=$(echo "$current_tag" | sed 's/^v//')
    if [ -n "$platform" ]; then
        base_version=$(echo "$base_version" | sed "s/-${platform}\$//")
    fi

    major=$(echo "$base_version" | cut -d. -f1)
    minor=$(echo "$base_version" | cut -d. -f2)
    patch=$(echo "$base_version" | cut -d. -f3)

    # Handle missing version components
    major="${major:-0}"
    minor="${minor:-0}"
    patch="${patch:-0}"

    # Analyze commits since last tag
    has_breaking=false
    has_feat=false
    has_fix=false

    # Use pipe instead of process substitution for POSIX compatibility
    git log "$current_tag"..HEAD --format=%s 2>/dev/null | while IFS= read -r msg; do
        [ -z "$msg" ] && continue
        if echo "$msg" | grep -qE "^[a-z]+(\(.+\))?!:"; then
            echo "BREAKING"
        elif echo "$msg" | grep -qE "^feat(\(.+\))?:"; then
            echo "FEAT"
        elif echo "$msg" | grep -qE "^(fix|perf|refactor)(\(.+\))?:"; then
            echo "FIX"
        fi
    done | {
        # Read commit types from pipe
        while IFS= read -r commit_type; do
            case "$commit_type" in
                BREAKING) has_breaking=true ;;
                FEAT) has_feat=true ;;
                FIX) has_fix=true ;;
            esac
        done

        # Bump version based on conventional commits
        if [ "$has_breaking" = true ]; then
            major=$((major + 1))
            minor=0
            patch=0
        elif [ "$has_feat" = true ]; then
            minor=$((minor + 1))
            patch=0
        elif [ "$has_fix" = true ]; then
            patch=$((patch + 1))
        else
            # No releasable commits - use current + dev suffix
            echo "${major}.${minor}.${patch}-dev"
            return
        fi

        echo "${major}.${minor}.${patch}"
    }
}

case "$0" in
    *get-next-version.sh) get_next_version "$@" ;;
esac

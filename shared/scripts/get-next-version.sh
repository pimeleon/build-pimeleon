#!/bin/sh
# Resolve the current version for a specific platform with Auto-Bump logic
# Usage: get-next-version.sh [platform]
#
# Version baseline resolution order:
#   1. Git tag matching *-{platform} or any tag (legacy)
#   2. apps/{platform}/VERSION file (used when no git tags exist)
#   3. 0.1.0 (fallback when nothing else is found)
#
# POSIX sh compatible - works in Alpine/BusyBox environments

set -eu

get_next_version() {
    platform="${1:-}"
    base_version=""
    git_range=""

    # 1. Try git tags first (legacy behavior)
    current_tag=""
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

    if [ -n "$current_tag" ]; then
        # Extract version from tag
        base_version=$(echo "$current_tag" | sed 's/^v//')
        if [ -n "$platform" ]; then
            base_version=$(echo "$base_version" | sed "s/-${platform}\$//")
        fi
        git_range="${current_tag}..HEAD"
    else
        # 2. Fall back to VERSION file
        version_file=""
        if [ -n "$platform" ]; then
            version_file="apps/${platform}/VERSION"
        fi

        if [ -n "$version_file" ] && [ -f "$version_file" ]; then
            base_version=$(tr -d '[:space:]' < "$version_file")

            # Find the last commit that changed the VERSION file to use as range start
            last_file_commit=$(git log --oneline -- "$version_file" 2>/dev/null | head -1 | awk '{print $1}')
            if [ -n "$last_file_commit" ]; then
                git_range="${last_file_commit}..HEAD"
            else
                # VERSION file exists but was never committed - no commits to analyze
                echo "$base_version"
                return
            fi
        else
            # 3. Final fallback
            echo "0.1.0"
            return
        fi
    fi

    major=$(echo "$base_version" | cut -d. -f1)
    minor=$(echo "$base_version" | cut -d. -f2)
    patch=$(echo "$base_version" | cut -d. -f3)

    # Handle missing version components
    major="${major:-0}"
    minor="${minor:-0}"
    patch="${patch:-0}"

    # Analyze commits in range to determine version bump type
    # Use pipe instead of process substitution for POSIX compatibility
    # shellcheck disable=SC2086
    git log $git_range --format=%s 2>/dev/null | while IFS= read -r msg; do
        [ -z "$msg" ] && continue
        if echo "$msg" | grep -qE "^[a-z]+(\(.+\))?!:"; then
            echo "BREAKING"
        elif echo "$msg" | grep -qE "^feat(\(.+\))?:"; then
            echo "FEAT"
        elif echo "$msg" | grep -qE "^(fix|perf|refactor)(\(.+\))?:"; then
            echo "FIX"
        fi
    done | {
        has_breaking=false
        has_feat=false
        has_fix=false

        while IFS= read -r commit_type; do
            case "$commit_type" in
                BREAKING) has_breaking=true ;;
                FEAT)     has_feat=true ;;
                FIX)      has_fix=true ;;
            esac
        done

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
            # No releasable commits since last version change
            echo "${major}.${minor}.${patch}-dev"
            return
        fi

        echo "${major}.${minor}.${patch}"
    }
}

case "$0" in
    *get-next-version.sh) get_next_version "$@" ;;
esac

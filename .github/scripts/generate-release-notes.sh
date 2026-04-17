#!/bin/bash
set -euo pipefail

# Generate release_notes.md from conventional commits since the last
# release-{platform}-v* tag on this repository.
#
# Inputs (env):
#   TARGET_PLATFORM — platform slug (e.g. rpi3-bookworm)
#   VERSION         — Pimeleon release version (e.g. 0.4.3)

PLATFORM="${TARGET_PLATFORM:-rpi3-bookworm}"
VERSION="${VERSION:-unknown}"

# Find the most recent release tag for this platform
PREV_TAG=$(git tag -l "release-${PLATFORM}-v*" | sort -V | tail -1 2>/dev/null || true)

if [ -n "$PREV_TAG" ]; then
    LOG_RANGE="${PREV_TAG}..HEAD"
    echo "[INFO] Changelog range: ${PREV_TAG}..HEAD"
else
    LOG_RANGE="HEAD"
    echo "[INFO] No previous release tag found — full history"
fi

# Extract commit subjects for a given conventional commit type prefix
_commits_of_type() {
    _type="$1"
    git log "$LOG_RANGE" --pretty=format:"%s" 2>/dev/null \
        | grep -E "^${_type}(\([^)]*\))?!?:" \
        | sed -E "s/^[a-z]+(\([^)]*\))?!?: /- /" \
        || true
}

{
    echo "## Pimeleon ${PLATFORM} v${VERSION}"
    echo ""

    for pair in "feat:Features" "fix:Bug Fixes" "perf:Performance Improvements" \
                "refactor:Refactoring" "docs:Documentation" "chore:Chores"; do
        _type="${pair%%:*}"
        _header="${pair#*:}"
        _lines=$(_commits_of_type "$_type")
        if [ -n "$_lines" ]; then
            echo "### ${_header}"
            echo "$_lines"
            echo ""
        fi
    done

    if [ -n "$PREV_TAG" ]; then
        echo "**Full diff**: [\`${PREV_TAG}\` → \`${PLATFORM}-v${VERSION}\`](../../compare/${PREV_TAG}...${PLATFORM}-v${VERSION})"
    fi
} > release_notes.md

echo "[INFO] Generated release_notes.md:"
cat release_notes.md

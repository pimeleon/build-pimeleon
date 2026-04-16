#!/bin/sh
set -eu
# Detect target platform from CI context.
# All CI builds use the single production profile.
# Writes TARGET_PLATFORM and PIMELEON_PROFILE to platform.env (dotenv artifact).
# POSIX-compatible (runs in alpine:latest which has no bash).
#
# Inputs (CI environment):
#   CI_PIPELINE_SOURCE, CI_MERGE_REQUEST_TARGET_BRANCH_NAME,
#   CI_COMMIT_BRANCH, TARGET_PLATFORM (web override)

if [ "${CI_PIPELINE_SOURCE:-}" = "merge_request_event" ]; then
    # MRs target a release platform when available, otherwise use the default platform.
    case "${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}" in
        release/*)
            PLATFORM=$(echo "$CI_MERGE_REQUEST_TARGET_BRANCH_NAME" | sed 's|^release/||')
            ;;
        *)
            PLATFORM="rpi3-bookworm"
            ;;
    esac
elif [ "${CI_PIPELINE_SOURCE:-}" = "web" ]; then
    PLATFORM="${TARGET_PLATFORM:-rpi3-bookworm}"
else
    case "${CI_COMMIT_BRANCH:-}" in
        release/*)
            PLATFORM=$(echo "$CI_COMMIT_BRANCH" | sed 's|^release/||')
            ;;
        *)
            # Direct push to develop or another non-release branch
            PLATFORM="rpi3-bookworm"
            ;;
    esac
fi

PROFILE="production"

# Resolve version via wrapper
SCRIPT_DIR="$(dirname "$0")"
PIMELEON_VERSION=$(sh "${SCRIPT_DIR}/resolve-version.sh" "$PLATFORM")

echo "TARGET_PLATFORM=$PLATFORM" > build.env
echo "PIMELEON_PROFILE=$PROFILE" >> build.env
echo "PIMELEON_VERSION=$PIMELEON_VERSION" >> build.env

echo "Platform detected: $PLATFORM"
echo "Profile selected: $PROFILE"
echo "Version resolved: $PIMELEON_VERSION"

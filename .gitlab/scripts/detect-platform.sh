#!/bin/sh
set -eu
# Detect target platform and build profile from CI context.
# Writes TARGET_PLATFORM and PIMELEON_PROFILE to platform.env (dotenv artifact).
# POSIX-compatible (runs in alpine:latest which has no bash).
#
# Inputs (CI environment):
#   CI_COMMIT_TAG, CI_PIPELINE_SOURCE, CI_MERGE_REQUEST_TARGET_BRANCH_NAME,
#   CI_COMMIT_BRANCH, TARGET_PLATFORM (web override), PIMELEON_PROFILE (web override)

if [ -n "${CI_COMMIT_TAG:-}" ]; then
  # Tag format: {platform}-v{version}, e.g., rpi4-bookworm-v1.2.3
  PLATFORM=$(echo "$CI_COMMIT_TAG" | sed 's/-v[0-9].*//')
  PROFILE="production"
elif [ "${CI_PIPELINE_SOURCE:-}" = "merge_request_event" ]; then
  # MRs always use development profile to avoid slow source builds
  case "${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}" in
    release/*)
      PLATFORM=$(echo "$CI_MERGE_REQUEST_TARGET_BRANCH_NAME" | sed 's|^release/||')
      ;;
    *)
      PLATFORM="rpi3-bookworm"
      ;;
  esac
  PROFILE="development"
elif [ "${CI_PIPELINE_SOURCE:-}" = "web" ]; then
  PLATFORM="${TARGET_PLATFORM:-rpi3-bookworm}"
  PROFILE="${PIMELEON_PROFILE:-production}"
else
  case "${CI_COMMIT_BRANCH:-}" in
    release/*)
      PLATFORM=$(echo "$CI_COMMIT_BRANCH" | sed 's|^release/||')
      PROFILE="production"
      ;;
    *)
      # Direct push to develop or other branch
      PLATFORM="rpi3-bookworm"
      PROFILE="development"
      ;;
  esac
fi

echo "TARGET_PLATFORM=$PLATFORM" > platform.env
echo "PIMELEON_PROFILE=$PROFILE" >> platform.env

# Detect architecture from platform name
case "$PLATFORM" in
  rpi4-*|rpi5-*) ARCH="arm64" ;;
  *)             ARCH="armhf" ;;
esac
echo "RPI_ARCH=$ARCH" >> platform.env

echo "Platform detected: $PLATFORM"
echo "Profile selected: $PROFILE"
echo "Architecture detected: $ARCH"

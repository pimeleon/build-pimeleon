#!/bin/bash
set -euo pipefail

# Generate a minimal release_notes.md for the GitHub Release step.
#
# Inputs (env):
#   TARGET_PLATFORM — platform slug (e.g. rpi3-bookworm)
#   VERSION         — Pimeleon release version

echo "Pimeleon release for ${TARGET_PLATFORM}" > release_notes.md
echo "Version: ${VERSION}"                     >> release_notes.md

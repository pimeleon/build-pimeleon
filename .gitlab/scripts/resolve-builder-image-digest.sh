#!/bin/sh
set -eu

# Resolve the registry digest for a builder image reference.
# Usage: resolve-builder-image-digest.sh <image_ref>

image_ref="${1:-${BUILD_IMAGE:-}}"

[ -n "${image_ref}" ] || { echo "[ERROR] image reference is required" >&2; exit 1; }

docker pull --quiet "${image_ref}" >/dev/null

repo_digest=$(docker image inspect --format '{{index .RepoDigests 0}}' "${image_ref}" 2>/dev/null || true)
[ -n "${repo_digest}" ] || { echo "[ERROR] Failed to resolve repo digest for ${image_ref}" >&2; exit 1; }

echo "${repo_digest##*@}"

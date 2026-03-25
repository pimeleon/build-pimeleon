#!/bin/sh
set -eu

echo "Uploading build artifacts from cache/output..."
ls -lh output/ 2>/dev/null || true

if [ -z "$(ls -A output/*.img 2>/dev/null)" ]; then
  echo "ERROR: No image artifacts found in output/. This indicates a cache miss or build failure."
  exit 1
fi

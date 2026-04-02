#!/bin/sh
set -eu

mkdir -p cache
CACHE_FILE="cache/pimeleon-${TARGET_PLATFORM}-base.tar.gz"

if [ -f "$CACHE_FILE" ]; then
    echo "Cache found: $CACHE_FILE"
    ls -lh "$CACHE_FILE"
else
    echo "Cache not found, will be created by build:pimeleon"
fi

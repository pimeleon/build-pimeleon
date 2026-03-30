#!/bin/sh
# Cleanup orphaned build container on job cancel/timeout/failure.
# Called from after_script — always runs regardless of job outcome.
if [ -f .build_container_id ]; then
    CID=$(cat .build_container_id)
    echo "Cleaning up build container: $CID"
    docker stop -t 10 "$CID" 2>/dev/null || true
    docker rm -f "$CID" 2>/dev/null || true
    rm -f .build_container_id
fi

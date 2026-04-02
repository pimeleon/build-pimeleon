#!/bin/sh
set -eu

mkdir -p "${TRIVY_CACHE_DIR}/db"

# Download DB if not cached
if [ ! -f "${TRIVY_CACHE_DIR}/db/trivy.db" ]; then
    echo "Downloading Trivy DB with retries..."
    for i in 1 2 3; do
        trivy image --download-db-only --cache-dir "${TRIVY_CACHE_DIR}" && break
        echo "Retry $i failed, waiting..."
        sleep 10
    done
fi

trivy fs --config trivy.yaml --cache-dir "${TRIVY_CACHE_DIR}" --skip-db-update --exit-code 0 --no-progress --scanners vuln --format json -o trivy-report.json .

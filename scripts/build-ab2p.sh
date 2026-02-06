#!/bin/bash
# Build adblock2privoxy image (run once, or when updating adblock2privoxy)
# This image is reused by the main builder, avoiding slow Haskell rebuilds

set -e

export DOCKER_BUILDKIT=1

cd "$(dirname "$0")/../shared/containers/builder"

echo "Building adblock2privoxy image (this may take several minutes on first run)..."
docker build \
    -f Dockerfile.ab2p \
    -t pimeleon-adblock2privoxy:latest \
    .

echo ""
echo "✅ adblock2privoxy image built successfully"
echo "   Image: pimeleon-adblock2privoxy:latest"
echo ""
echo "This image will be reused by subsequent builder builds."
echo "Only re-run this script if you need to update adblock2privoxy."

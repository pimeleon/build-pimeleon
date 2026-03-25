#!/bin/sh
set -eu

# Check whether builder and tester images already exist in the registry

if docker manifest inspect "$BUILD_IMAGE" >/dev/null 2>&1 && \
   docker manifest inspect "$TEST_IMAGE" >/dev/null 2>&1; then
  echo "CONTAINERS_EXIST=true" >> containers.env
  echo "Builder and tester images already in registry — build will be skipped"
else
  echo "CONTAINERS_EXIST=false" >> containers.env
  echo "Images not found in registry — build required"
fi
